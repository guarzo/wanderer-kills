defmodule WandererKills.External.ZKB.RedisQ do
  @moduledoc """
  Client for interacting with the zKillboard RedisQ API.

  This module handles streaming killmail data from zKillboard's RedisQ endpoint,
  providing real-time killmail processing capabilities.

  ## Format Handling and Monitoring

  Analysis confirmed two response formats from RedisQ:
  1. **Package with full killmail**: `%{"package" => %{"killmail" => data, "zkb" => zkb}}`
  2. **Package null**: `%{"package" => nil}` - no activity

  **Production Usage**: 100% package_full format - no legacy formats observed.
  **Monitoring**: This module tracks format usage for operational visibility.

  ## Polling Behavior

  • Idle (no kills):    poll every `:idle_interval_ms`
  • On kill (new):      poll again after `:fast_interval_ms`
  • On kill_older:      poll again after `:idle_interval_ms` (reset backoff)
  • On kill_skipped:    poll again after `:idle_interval_ms` (reset backoff)
  • On error:           exponential backoff up to `:max_backoff_ms`
  """

  use GenServer
  require Logger

  alias WandererKills.Infrastructure.Clock
  alias WandererKills.Http.Client, as: HttpClient

  @user_agent "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"

  @base_url Application.compile_env(:wanderer_kills, :redisq_base_url)

  defmodule State do
    @moduledoc false
    defstruct [:queue_id, :backoff_ms]
  end

  #
  # Public API
  #

  @doc """
  Gets the base URL for RedisQ API calls.
  """
  def base_url do
    @base_url
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
  Starts listening to RedisQ killmail stream.
  """
  def start_listening do
    url = "#{base_url()}?queueID=wanderer-kills"

    case HttpClient.get_with_rate_limit(url) do
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
    initial_back = get_config(:initial_backoff_ms)

    Logger.info("[RedisQ] Initialized with queue ID: #{queue_id}")
    # Schedule the very first poll after the idle interval
    schedule_poll(get_config(:idle_interval_ms))

    state = %State{queue_id: queue_id, backoff_ms: initial_back}
    {:ok, state}
  end

  @impl true
  def handle_info(:poll_kills, %State{queue_id: qid, backoff_ms: backoff} = state) do
    Logger.debug("[RedisQ] Polling RedisQ (queue ID: #{qid})")
    result = do_poll(qid)

    {delay_ms, new_backoff} = next_schedule(result, backoff)
    schedule_poll(delay_ms)

    {:noreply, %State{state | backoff_ms: new_backoff}}
  end

  @impl true
  def handle_call({:poll_and_process, _opts}, _from, %State{queue_id: qid} = state) do
    Logger.debug("[RedisQ] Manual poll requested (queue ID: #{qid})")
    reply = do_poll(qid)
    {:reply, reply, state}
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

  # Perform the actual HTTP GET + parsing and return one of:
  #   - {:ok, :kill_received}
  #   - {:ok, :no_kills}
  #   - {:ok, :kill_older}
  #   - {:ok, :kill_skipped}
  #   - {:error, reason}
  defp do_poll(queue_id) do
    url = "#{base_url()}?queueID=#{queue_id}&ttw=1"
    Logger.debug("[RedisQ] GET #{url}")

    case HttpClient.get_with_rate_limit(url, headers: [{"user-agent", @user_agent}]) do
      # No package → no new kills
      {:ok, %{body: %{"package" => nil}}} ->
        Logger.debug("[RedisQ] No package received.")
        {:ok, :no_kills}

      # Package format with full killmail data (confirmed production format)
      {:ok, %{body: %{"package" => %{"killmail" => killmail, "zkb" => zkb}}}} ->
        Logger.info("[RedisQ] Package format with full killmail received",
          format: :package_full,
          endpoint: url
        )

        track_format_usage(:package_full)
        process_kill(killmail, zkb)

      # Anything else is unexpected
      {:ok, resp} ->
        Logger.warning("[RedisQ] Unexpected response shape",
          response: inspect(resp),
          endpoint: url
        )

        track_format_usage(:unexpected)
        {:error, :unexpected_format}

      {:error, reason} ->
        Logger.warning("[RedisQ] HTTP request failed",
          error: inspect(reason),
          endpoint: url
        )

        {:error, reason}
    end
  end

  # Handle a "new‐format" killmail JSON blob.  Return one of:
  #   {:ok, :kill_received}   if it's a brand-new kill
  #   {:ok, :kill_older}      if parser determined it's older than cutoff
  #   {:ok, :kill_skipped}    if parser determined we already ingested it
  #   {:error, reason}
  #
  # This requires that Parser.parse_full_and_store/3 returns exactly
  #   {:ok, :kill_older}   or
  #   {:ok, :kill_skipped}
  # when appropriate—otherwise, we treat any other {:ok, _} as :kill_received.
  defp process_kill(killmail, zkb) do
    cutoff = get_cutoff_time()

    # Log detailed information about the format and available data
    killmail_id = Map.get(killmail, "killmail_id", "unknown")
    victim_ship = get_in(killmail, ["victim", "ship_type_id"])
    attacker_count = length(Map.get(killmail, "attackers", []))

    Logger.debug(
      "[RedisQ] Processing new format killmail (cutoff: #{DateTime.to_iso8601(cutoff)})",
      killmail_id: killmail_id,
      format: :full_killmail_data,
      victim_ship_type_id: victim_ship,
      attacker_count: attacker_count,
      has_zkb_data: not is_nil(zkb)
    )

    case WandererKills.Killmails.Coordinator.parse_full_and_store(
           killmail,
           %{"zkb" => zkb},
           cutoff
         ) do
      {:ok, :kill_older} ->
        Logger.debug("[RedisQ] Kill is older than cutoff → skipping.")
        {:ok, :kill_older}

      {:ok, _any_other} ->
        Logger.debug("[RedisQ] Successfully parsed & stored new killmail.")
        {:ok, :kill_received}

      {:error, reason} ->
        Logger.error("[RedisQ] Failed to parse/store killmail: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Decide the next polling interval and updated backoff based on the last result.
  # Returns: {next_delay_ms, updated_backoff_ms}
  defp next_schedule({:ok, :kill_received}, _old_backoff) do
    fast = get_config(:fast_interval_ms)
    Logger.debug("[RedisQ] Kill received → scheduling next poll in #{fast}ms; resetting backoff.")
    {fast, get_config(:initial_backoff_ms)}
  end

  defp next_schedule({:ok, :no_kills}, _old_backoff) do
    idle = get_config(:idle_interval_ms)
    Logger.debug("[RedisQ] No kills → scheduling next poll in #{idle}ms; resetting backoff.")
    {idle, get_config(:initial_backoff_ms)}
  end

  defp next_schedule({:ok, :kill_older}, _old_backoff) do
    idle = get_config(:idle_interval_ms)

    Logger.debug(
      "[RedisQ] Older kill detected → scheduling next poll in #{idle}ms; resetting backoff."
    )

    {idle, get_config(:initial_backoff_ms)}
  end

  defp next_schedule({:error, reason}, old_backoff) do
    factor = get_config(:backoff_factor)
    max_back = get_config(:max_backoff_ms)
    next_back = min(old_backoff * factor, max_back)

    Logger.warning("[RedisQ] Poll error: #{inspect(reason)} → retry in #{next_back}ms (backoff).")

    {next_back, next_back}
  end

  # Build a simple unique queue ID similar to "Voltron9000":
  #   "WK<random_number>" (8-10 chars total)
  defp build_queue_id do
    # Generate a random number between 1000 and 999999 for uniqueness
    random_num = :rand.uniform(999_000) + 1000

    "WK#{random_num}"
  end

  # Returns cutoff DateTime (e.g. "24 hours ago")
  defp get_cutoff_time do
    Clock.hours_ago(24)
  end

  # Fetch configuration using the new flattened structure
  defp get_config(key) do
    WandererKills.Infrastructure.Config.redisq(key)
  end

  # Track format usage for monitoring and analysis
  defp track_format_usage(format_type) do
    # Emit telemetry event
    :telemetry.execute(
      [:wanderer_kills, :redisq, :format],
      %{count: 1},
      %{
        format: format_type,
        timestamp: DateTime.utc_now(),
        module: __MODULE__
      }
    )

    # Also log a summary periodically (every 100 calls)
    case :persistent_term.get({__MODULE__, :format_counter}, 0) do
      count when rem(count, 100) == 0 and count > 0 ->
        format_stats = :persistent_term.get({__MODULE__, :format_stats}, %{})

        Logger.info("[RedisQ] Format usage summary",
          stats: format_stats,
          total_calls: count
        )

      _count ->
        :ok
    end

    # Update counters
    new_count = :persistent_term.get({__MODULE__, :format_counter}, 0) + 1
    :persistent_term.put({__MODULE__, :format_counter}, new_count)

    current_stats = :persistent_term.get({__MODULE__, :format_stats}, %{})
    updated_stats = Map.update(current_stats, format_type, 1, &(&1 + 1))
    :persistent_term.put({__MODULE__, :format_stats}, updated_stats)
  end

  defp handle_response(%{"package" => package}) do
    # Process the killmail package
    Logger.info("Received killmail package: #{inspect(package)}")
  end

  defp handle_response(_) do
    # No package in response, continue listening
    start_listening()
  end
end
