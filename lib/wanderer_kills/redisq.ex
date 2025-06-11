defmodule WandererKills.RedisQ do
  @moduledoc """
  Client for interacting with the zKillboard RedisQ API.

  • Idle (no kills):    poll every `:idle_interval_ms`
  • On kill (new):      poll again after `:fast_interval_ms`
  • On kill_older:      poll again after `:idle_interval_ms` (reset backoff)
  • On kill_skipped:    poll again after `:idle_interval_ms` (reset backoff)
  • On error:           exponential backoff up to `:max_backoff_ms`
  """

  use GenServer
  require Logger

  alias WandererKills.Killmails.UnifiedProcessor
  alias WandererKills.ESI.DataFetcher, as: EsiClient
  alias WandererKills.Support.Clock
  alias WandererKills.Http.Client, as: HttpClient
  alias WandererKills.Config

  @user_agent "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"

  defmodule State do
    @moduledoc false
    defstruct [:queue_id, :backoff_ms, :stats]
  end

  #
  # Public API
  #

  @doc """
  Gets the base URL for RedisQ API calls.
  """
  def base_url do
    Config.services().redisq_base_url || "https://zkillredisq.stream/listen.php"
  end

  @doc """
  Starts the RedisQ worker as a GenServer.
  """
  def start_link(opts \\ []) do
    Logger.info("[RedisQ] Starting RedisQ worker")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Force a synchronous poll & process. Returns one of:
    - `{:ok, :kill_received}`
    - `{:ok, :no_kills}`
    - `{:ok, :kill_older}`
    - `{:ok, :kill_skipped}`
    - `{:error, reason}`
  """
  def poll_and_process(opts \\ []) do
    GenServer.call(__MODULE__, {:poll_and_process, opts})
  end

  @doc """
  Gets current RedisQ statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Starts listening to RedisQ killmail stream.
  """
  def start_listening do
    url = "#{base_url()}?queueID=wanderer-kills"

    case HttpClient.get(url) do
      {:ok, %{body: body}} ->
        handle_response(body)

      {:error, reason} ->
        Logger.error("Failed to get RedisQ response: #{inspect(reason)}")
    end
  end

  #
  # Server Callbacks
  #

  @impl true
  def init(_opts) do
    queue_id = build_queue_id()
    initial_backoff = Config.redisq().initial_backoff_ms

    # Initialize statistics tracking
    stats = %{
      kills_received: 0,
      kills_older: 0,
      kills_skipped: 0,
      legacy_kills: 0,
      errors: 0,
      no_kills_count: 0,
      last_reset: DateTime.utc_now(),
      systems_active: MapSet.new(),
      # Cumulative stats that don't reset
      total_kills_received: 0,
      total_kills_older: 0,
      total_kills_skipped: 0,
      total_legacy_kills: 0,
      total_errors: 0,
      total_no_kills_count: 0
    }

    state = %State{queue_id: queue_id, backoff_ms: initial_backoff, stats: stats}
    {:ok, state, {:continue, :start_polling}}
  end

  @impl true
  def handle_continue(:start_polling, state) do
    Logger.info("[RedisQ] Starting polling with queue ID: #{state.queue_id}")
    # Schedule the very first poll after the idle interval
    schedule_poll(Config.redisq().idle_interval_ms)
    # Schedule the first summary log
    schedule_summary_log()
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_kills, %State{queue_id: qid, backoff_ms: backoff, stats: stats} = state) do
    Logger.debug("[RedisQ] Polling RedisQ (queue ID: #{qid})")
    result = do_poll(qid)

    # Update statistics based on result
    new_stats = update_stats(stats, result)

    {delay_ms, new_backoff} = next_schedule(result, backoff)
    schedule_poll(delay_ms)

    {:noreply, %State{state | backoff_ms: new_backoff, stats: new_stats}}
  end

  @impl true
  def handle_info(:log_summary, %State{stats: stats} = state) do
    log_summary(stats)

    # Reset stats and schedule next summary
    reset_stats = %{
      stats
      | kills_received: 0,
        kills_older: 0,
        kills_skipped: 0,
        legacy_kills: 0,
        errors: 0,
        no_kills_count: 0,
        last_reset: DateTime.utc_now(),
        systems_active: MapSet.new()
    }

    schedule_summary_log()
    {:noreply, %State{state | stats: reset_stats}}
  end

  @impl true
  def handle_info({:track_system, system_id}, %State{stats: stats} = state) do
    new_stats = track_system_activity(stats, system_id)
    {:noreply, %State{state | stats: new_stats}}
  end

  @impl true
  def handle_call({:poll_and_process, _opts}, _from, %State{queue_id: qid} = state) do
    Logger.debug("[RedisQ] Manual poll requested (queue ID: #{qid})")
    reply = do_poll(qid)
    {:reply, reply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      # Use cumulative stats for the 5-minute report
      kills_processed: state.stats.total_kills_received,
      kills_older: state.stats.total_kills_older,
      kills_skipped: state.stats.total_kills_skipped,
      legacy_kills: state.stats.total_legacy_kills,
      errors: state.stats.total_errors,
      no_kills_polls: state.stats.total_no_kills_count,
      active_systems: MapSet.size(state.stats.systems_active),
      total_polls:
        state.stats.total_kills_received + state.stats.total_kills_older +
          state.stats.total_kills_skipped + state.stats.total_legacy_kills +
          state.stats.total_no_kills_count + state.stats.total_errors,
      last_reset: state.stats.last_reset
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def terminate(_reason, _state), do: :ok

  #
  # Private Helpers
  #

  # Schedules the next :poll_kills message in `ms` milliseconds.
  defp schedule_poll(ms) do
    Process.send_after(self(), :poll_kills, ms)
  end

  # Schedules the next :log_summary message in 60 seconds.
  defp schedule_summary_log do
    Process.send_after(self(), :log_summary, 60_000)
  end

  # Updates statistics based on poll result
  defp update_stats(stats, {:ok, :kill_received}) do
    %{
      stats
      | kills_received: stats.kills_received + 1,
        total_kills_received: stats.total_kills_received + 1
    }
  end

  defp update_stats(stats, {:ok, :kill_older}) do
    %{stats | kills_older: stats.kills_older + 1, total_kills_older: stats.total_kills_older + 1}
  end

  defp update_stats(stats, {:ok, :kill_skipped}) do
    %{
      stats
      | kills_skipped: stats.kills_skipped + 1,
        total_kills_skipped: stats.total_kills_skipped + 1
    }
  end

  defp update_stats(stats, {:ok, :no_kills}) do
    %{
      stats
      | no_kills_count: stats.no_kills_count + 1,
        total_no_kills_count: stats.total_no_kills_count + 1
    }
  end

  defp update_stats(stats, {:error, _reason}) do
    %{stats | errors: stats.errors + 1, total_errors: stats.total_errors + 1}
  end

  # Track active systems
  defp track_system_activity(stats, system_id) when is_integer(system_id) do
    %{stats | systems_active: MapSet.put(stats.systems_active, system_id)}
  end

  defp track_system_activity(stats, _), do: stats

  # Log summary of activity over the past minute
  defp log_summary(stats) do
    duration = DateTime.diff(DateTime.utc_now(), stats.last_reset, :second)

    total_activity =
      stats.kills_received + stats.kills_older + stats.kills_skipped + stats.legacy_kills

    if total_activity > 0 or stats.errors > 0 do
      # Get websocket stats from the observability module
      ws_stats =
        case WandererKills.Observability.WebSocketStats.get_stats() do
          {:ok, stats} -> stats
          _ -> %{kills_sent: %{total: 0, realtime: 0, preload: 0}}
        end

      Logger.info(
        "📊 REDISQ SUMMARY (#{duration}s): " <>
          "Kills processed: #{stats.kills_received}, " <>
          "Older kills: #{stats.kills_older}, " <>
          "Skipped: #{stats.kills_skipped}, " <>
          "Legacy: #{stats.legacy_kills}, " <>
          "No-kill polls: #{stats.no_kills_count}, " <>
          "Errors: #{stats.errors}, " <>
          "Active systems: #{MapSet.size(stats.systems_active)}, " <>
          "Total polls: #{total_activity + stats.no_kills_count + stats.errors}, " <>
          "WS kills sent: #{ws_stats.kills_sent.total} (RT: #{ws_stats.kills_sent.realtime}, PL: #{ws_stats.kills_sent.preload})",
        kills_processed: stats.kills_received,
        kills_older: stats.kills_older,
        kills_skipped: stats.kills_skipped,
        legacy_kills: stats.legacy_kills,
        no_kills_polls: stats.no_kills_count,
        errors: stats.errors,
        active_systems: MapSet.size(stats.systems_active),
        total_polls: total_activity + stats.no_kills_count + stats.errors
      )
    end
  end

  # Perform the actual HTTP GET + parsing and return one of:
  #   - {:ok, :kill_received}
  #   - {:ok, :no_kills}
  #   - {:ok, :kill_older}
  #   - {:ok, :kill_skipped}
  #   - {:error, reason}
  defp do_poll(queue_id) do
    url = "#{base_url()}?queueID=#{queue_id}&ttw=1"
    Logger.debug("[RedisQ] GET #{url}")

    headers = [{"user-agent", @user_agent}]

    case HttpClient.get(url, headers) do
      # No package → no new kills
      {:ok, %{body: %{"package" => nil}}} ->
        Logger.debug("[RedisQ] No package received.")
        {:ok, :no_kills}

      # New‐format: "package" → %{ "killID" => _, "killmail" => killmail, "zkb" => zkb }
      {:ok, %{body: %{"package" => %{"killID" => _id, "killmail" => killmail, "zkb" => zkb}}}} ->
        process_kill(killmail, zkb)

      # Alternate new‐format (sometimes `killID` is absent, but `killmail`+`zkb` exist)
      {:ok, %{body: %{"package" => %{"killmail" => killmail, "zkb" => zkb}}}} ->
        process_kill(killmail, zkb)

      # Legacy format: { "killID" => id, "zkb" => zkb }
      {:ok, %{body: %{"killID" => id, "zkb" => zkb}}} ->
        process_legacy_kill(id, zkb)

      # Anything else is unexpected
      {:ok, resp} ->
        Logger.warning("[RedisQ] Unexpected response shape: #{inspect(resp)}")
        {:error, :unexpected_format}

      {:error, reason} ->
        Logger.warning("[RedisQ] HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Handle a "new‐format" killmail JSON blob.  Return one of:
  #   {:ok, :kill_received}   if it's a brand-new kill
  #   {:ok, :kill_older}      if parser determined it's older than cutoff
  #   {:ok, :kill_skipped}    if parser determined we already ingested it
  #   {:error, reason}
  #
  # This requires that Coordinator.parse_full_and_store/3 returns exactly
  #   {:ok, :kill_older}   or
  #   {:ok, :kill_skipped}
  # when appropriate—otherwise, we treat any other {:ok, _} as :kill_received.
  defp process_kill(killmail, zkb) do
    cutoff = get_cutoff_time()

    Logger.debug(
      "[RedisQ] Processing new format killmail (cutoff: #{DateTime.to_iso8601(cutoff)})"
    )

    merged = Map.merge(killmail, %{"zkb" => zkb})

    case UnifiedProcessor.process_killmail(merged, cutoff) do
      {:ok, :kill_older} ->
        Logger.debug("[RedisQ] Kill is older than cutoff → skipping.")
        {:ok, :kill_older}

      {:ok, enriched_killmail} ->
        Logger.debug("[RedisQ] Successfully parsed & stored new killmail.")

        # Broadcast kill update via PubSub using the enriched killmail
        broadcast_killmail_update_enriched(enriched_killmail)

        {:ok, :kill_received}

      {:error, reason} ->
        Logger.error("[RedisQ] Failed to parse/store killmail: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Handle legacy‐format kill → fetch full payload async and then process.
  # Returns one of:
  #   {:ok, :kill_received}   (if Coordinator.parse... says new)
  #   {:ok, :kill_older}      (if Coordinator returns :kill_older)
  #   {:ok, :kill_skipped}    (if Coordinator returns :kill_skipped)
  #   {:error, reason}
  defp process_legacy_kill(id, zkb) do
    task =
      Task.Supervisor.async(WandererKills.TaskSupervisor, fn ->
        fetch_and_parse_full_kill(id, zkb)
      end)

    task
    |> Task.await(Config.redisq().task_timeout_ms)
    |> case do
      {:ok, :kill_received} ->
        {:ok, :kill_received}

      {:ok, :kill_older} ->
        Logger.debug("[RedisQ] Legacy kill ID=#{id} is older than cutoff → skipping.")
        {:ok, :kill_older}

      {:ok, :kill_skipped} ->
        Logger.debug("[RedisQ] Legacy kill ID=#{id} already ingested → skipping.")
        {:ok, :kill_skipped}

      {:error, reason} ->
        Logger.error("[RedisQ] Legacy‐kill #{id} failed: #{inspect(reason)}")
        {:error, reason}

      other ->
        Logger.error("[RedisQ] Unexpected task result for legacy kill #{id}: #{inspect(other)}")
        {:error, :unexpected_task_result}
    end
  end

  # Fetch the full killmail from ESI and then hand off to `process_kill/2`.
  # Returns exactly whatever `process_kill/2` returns.
  defp fetch_and_parse_full_kill(id, zkb) do
    Logger.debug("[RedisQ] Fetching full killmail for ID=#{id}")

    case EsiClient.get_killmail_raw(id, zkb["hash"]) do
      {:ok, full_killmail} ->
        Logger.debug("[RedisQ] Fetched full killmail ID=#{id}. Now parsing…")
        process_kill(full_killmail, zkb)

      {:error, reason} ->
        Logger.warning("[RedisQ] ESI fetch failed for ID=#{id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Decide the next polling interval and updated backoff based on the last result.
  # Returns: {next_delay_ms, updated_backoff_ms}
  defp next_schedule({:ok, :kill_received}, _old_backoff) do
    fast = Config.redisq().fast_interval_ms
    Logger.debug("[RedisQ] Kill received → scheduling next poll in #{fast}ms; resetting backoff.")
    {fast, Config.redisq().initial_backoff_ms}
  end

  defp next_schedule({:ok, :no_kills}, _old_backoff) do
    idle = Config.redisq().idle_interval_ms
    Logger.debug("[RedisQ] No kills → scheduling next poll in #{idle}ms; resetting backoff.")
    {idle, Config.redisq().initial_backoff_ms}
  end

  defp next_schedule({:ok, :kill_older}, _old_backoff) do
    idle = Config.redisq().idle_interval_ms

    Logger.debug(
      "[RedisQ] Older kill detected → scheduling next poll in #{idle}ms; resetting backoff."
    )

    {idle, Config.redisq().initial_backoff_ms}
  end

  defp next_schedule({:ok, :kill_skipped}, _old_backoff) do
    idle = Config.redisq().idle_interval_ms

    Logger.debug(
      "[RedisQ] Skipped kill detected → scheduling next poll in #{idle}ms; resetting backoff."
    )

    {idle, Config.redisq().initial_backoff_ms}
  end

  defp next_schedule({:error, reason}, old_backoff) do
    factor = Config.redisq().backoff_factor
    max_back = Config.redisq().max_backoff_ms
    next_back = min(old_backoff * factor, max_back)

    Logger.warning("[RedisQ] Poll error: #{inspect(reason)} → retry in #{next_back}ms (backoff).")

    {next_back, next_back}
  end

  # Build a unique queue ID: "wanderer_kills_<16_char_string>"
  # Uses a mix of timestamp and random characters for uniqueness
  defp build_queue_id do
    # Generate 16 character random string using alphanumeric characters
    random_chars =
      for _ <- 1..16,
          into: "",
          do: <<Enum.random(~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")>>

    "wanderer_kills_#{random_chars}"
  end

  # Returns cutoff DateTime (e.g. "24 hours ago")
  defp get_cutoff_time do
    Clock.hours_ago(1)
  end

  defp handle_response(%{"package" => package}) do
    # Process the killmail package
    Logger.debug("Received killmail package: #{inspect(package)}")
  end

  defp handle_response(_) do
    # No package in response, continue listening
    start_listening()
  end

  # Broadcast killmail update to PubSub subscribers using enriched killmail
  defp broadcast_killmail_update_enriched(enriched_killmail) do
    system_id =
      Map.get(enriched_killmail, "solar_system_id") || Map.get(enriched_killmail, "system_id")

    killmail_id = Map.get(enriched_killmail, "killmail_id")

    if system_id do
      # Track system activity for statistics
      send(self(), {:track_system, system_id})

      # Broadcast detailed kill update
      WandererKills.SubscriptionManager.broadcast_killmail_update_async(system_id, [
        enriched_killmail
      ])

      # Also broadcast kill count update (increment by 1)
      WandererKills.SubscriptionManager.broadcast_killmail_count_update_async(system_id, 1)
    else
      Logger.warning("[RedisQ] Cannot broadcast killmail update - missing system_id",
        killmail_id: killmail_id
      )
    end
  end
end
