defmodule WandererKills.Preloader.RedisQ do
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

  alias WandererKills.Parser
  alias WandererKills.Esi.Cache, as: EsiCache
  alias WandererKills.Core.Clock
  alias WandererKills.Http.Client, as: HttpClient

  @user_agent "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"

  @base_url Application.compile_env(:wanderer_kills, [:redisq, :base_url])

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

      # New‐format: "package" → %{ "killID" => _, "killmail" => killmail, "zkb" => zkb }
      {:ok, %{body: %{"package" => %{"killID" => _id, "killmail" => killmail, "zkb" => zkb}}}} ->
        Logger.info("[RedisQ] New‐format killmail received.")
        process_kill(killmail, zkb)

      # Alternate new‐format (sometimes `killID` is absent, but `killmail`+`zkb` exist)
      {:ok, %{body: %{"package" => %{"killmail" => killmail, "zkb" => zkb}}}} ->
        Logger.info("[RedisQ] New‐format killmail (no killID) received.")
        process_kill(killmail, zkb)

      # Legacy format: { "killID" => id, "zkb" => zkb }
      {:ok, %{body: %{"killID" => id, "zkb" => zkb}}} ->
        Logger.info("[RedisQ] Legacy‐format killmail ID=#{id}.  Fetching full payload…")
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
  # This requires that Parser.parse_full_and_store/3 returns exactly
  #   {:ok, :kill_older}   or
  #   {:ok, :kill_skipped}
  # when appropriate—otherwise, we treat any other {:ok, _} as :kill_received.
  defp process_kill(killmail, zkb) do
    cutoff = get_cutoff_time()

    Logger.debug(
      "[RedisQ] Processing new format killmail (cutoff: #{DateTime.to_iso8601(cutoff)})"
    )

    case Parser.parse_full_and_store(killmail, %{"zkb" => zkb}, cutoff) do
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

  # Handle legacy‐format kill → fetch full payload async and then process.
  # Returns one of:
  #   {:ok, :kill_received}   (if Parser.parse... says new)
  #   {:ok, :kill_older}      (if Parser returns :kill_older)
  #   {:ok, :kill_skipped}    (if Parser returns :kill_skipped)
  #   {:error, reason}
  defp process_legacy_kill(id, zkb) do
    task =
      Task.Supervisor.async(WandererKills.TaskSupervisor, fn ->
        fetch_and_parse_full_kill(id, zkb)
      end)

    task
    |> Task.await(get_config(:task_timeout_ms))
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

    case EsiCache.get_killmail(id, zkb["hash"]) do
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

  defp next_schedule({:ok, :kill_skipped}, _old_backoff) do
    idle = get_config(:idle_interval_ms)

    Logger.debug(
      "[RedisQ] Skipped kill detected → scheduling next poll in #{idle}ms; resetting backoff."
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

  # Fetch an integer or float from application config under [:wanderer_kills, :redisq].
  # The config is expected to be a map. If the key is missing, this will raise.
  defp get_config(key) do
    cfg = Application.fetch_env!(:wanderer_kills, :redisq)

    # cfg is a map like:
    # %{
    #   task_timeout_ms:    10_000,
    #   fast_interval_ms:   1_000,
    #   idle_interval_ms:   5_000,
    #   initial_backoff_ms: 1_000,
    #   max_backoff_ms:     30_000,
    #   backoff_factor:     2
    # }
    Map.fetch!(cfg, key)
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
