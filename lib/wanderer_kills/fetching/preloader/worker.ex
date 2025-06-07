defmodule WandererKills.Preloader.Worker do
  @moduledoc """
  Preloads killmail data for systems.

  On startup:
    1. Runs a one-off quick preload (last 1h, limit 5).
    2. Exposes `run_preload_now/0` for an expanded preload (last 24h, limit 100).

  The preloader maintains a list of active systems based on API requests,
  with a 24-hour TTL for each system.
  """

  use GenServer
  require Logger

  alias WandererKills.Core.Cache

  @type pass_type :: :quick | :expanded
  @type fetch_result :: :ok | {:error, term()}

  @passes %{
    quick: %{hours: 1, limit: 5},
    expanded: %{hours: 24, limit: 100}
  }

  @default_max_concurrency 2

  ## Public API

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @doc """
  Starts the KillsPreloader GenServer.

  Options:
    - `:max_concurrency` (integer, default: #{@default_max_concurrency})
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an expanded preload pass (last 24h, limit 100).
  """
  @spec run_preload_now() :: :ok
  def run_preload_now do
    GenServer.cast(__MODULE__, :run_expanded_pass)
  end

  @doc """
  Adds a system to the active systems list and triggers a preload.
  """
  @spec add_system(integer()) :: :ok
  def add_system(system_id) when is_integer(system_id) do
    Logger.info("Adding system to active list",
      system_id: system_id,
      operation: :add_system,
      step: :start
    )

    case Cache.add_active_system(system_id) do
      {:ok, :added} ->
        Logger.info("Successfully added system to active list",
          system_id: system_id,
          operation: :add_system,
          status: :success
        )

        :ok

      {:ok, :already_exists} ->
        Logger.info("System already in active list",
          system_id: system_id,
          operation: :add_system,
          status: :already_exists
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to add system to active list",
          system_id: system_id,
          operation: :add_system,
          error: reason,
          status: :error
        )

        {:error, reason}
    end
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)

    # Temporarily load a single system for testing and logging
    # Jita system ID for testing
    test_system_id = 30_000_142

    Logger.info("Preloader starting - adding test system for validation",
      system_id: test_system_id,
      purpose: :foundation_testing
    )

    # Add the test system to active systems
    case Cache.add_active_system(test_system_id) do
      {:ok, :added} ->
        Logger.info("Successfully added test system",
          system_id: test_system_id,
          status: :success
        )

        # Spawn a quick preload for the test system
        spawn_test_preload_task(test_system_id)

      {:ok, :already_exists} ->
        Logger.info("Test system already in active list",
          system_id: test_system_id,
          status: :already_exists
        )

        # Still spawn a test task
        spawn_test_preload_task(test_system_id)

      {:error, reason} ->
        Logger.warning("Failed to add test system",
          system_id: test_system_id,
          error: reason
        )
    end

    # Check for any existing active systems
    case Cache.get_active_systems() do
      {:ok, systems} when is_list(systems) ->
        Logger.info("Preloader initialized with #{length(systems)} active systems")
        {:ok, %{max_concurrency: max_concurrency}}

      {:error, reason} ->
        Logger.error("Failed to initialize preloader: #{inspect(reason)}")
        {:ok, %{max_concurrency: max_concurrency}}
    end
  end

  @impl true
  def handle_cast(:run_expanded_pass, %{max_concurrency: _max} = state) do
    case Cache.get_active_systems() do
      {:ok, systems} when is_list(systems) ->
        Logger.info("Starting preload pass for #{length(systems)} systems")

        for system_id <- systems do
          Logger.debug("Processing system in preload pass", system_id: system_id)
          # Add any system-specific processing here
        end

        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to get active systems: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    # Only log actual crashes, not normal exits or expected errors
    case reason do
      :normal -> :ok
      :no_active_systems -> :ok
      _ -> Logger.error("[Preloader] Preload task crashed: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  ## Internal

  @doc """
  Spawns a new pass task under the task supervisor.
  """
  def spawn_pass(pass_type, max_concurrency) do
    task =
      Task.Supervisor.async_nolink(
        WandererKills.TaskSupervisor,
        fn -> do_pass(pass_type, max_concurrency) end,
        shutdown: :brutal_kill
      )

    Logger.info("Spawned #{pass_type} pass task")
    task
  end

  @spec do_pass(pass_type(), pos_integer()) :: :ok
  defp do_pass(pass_type, _max_concurrency) do
    %{hours: hours, limit: limit} = @passes[pass_type]
    start_time = System.monotonic_time(:millisecond)

    case Cache.get_active_systems() do
      {:ok, systems} when is_list(systems) and length(systems) > 0 ->
        Logger.info("Processing #{length(systems)} active systems")

        systems
        |> Enum.each(fn system_id ->
          Logger.debug("Processing system", system_id: system_id)
          fetch_system(system_id, hours, limit)
        end)

        log_stats(pass_type, systems, start_time)

      {:ok, []} ->
        Logger.info("[Preloader] No active systems to preload")
        :ok

      {:error, reason} ->
        Logger.error("[Preloader] Failed to get active systems: #{inspect(reason)}")
        :ok
    end
  end

  defp log_stats(type, ids, start_ms) do
    elapsed_s = (System.monotonic_time(:millisecond) - start_ms) / 1_000

    Logger.info("""
    Completed #{type} preload:
      • Systems: #{length(ids)}
      • Elapsed: #{Float.round(elapsed_s, 2)}s
    """)
  end

  # Spawns a test preload task for validation during initialization
  @spec spawn_test_preload_task(integer()) :: {:ok, pid()}
  defp spawn_test_preload_task(test_system_id) do
    Task.start(fn ->
      # Wait for system to be fully initialized
      Process.sleep(2000)

      Logger.info("Running test preload for validation",
        system_id: test_system_id
      )

      case fetch_system(test_system_id, 1, 3) do
        :ok ->
          Logger.info("Test system preload completed successfully",
            system_id: test_system_id,
            status: :success
          )

        {:error, reason} ->
          Logger.warning("Test system preload failed",
            system_id: test_system_id,
            error: reason,
            status: :error
          )
      end
    end)
  end

  @spec fetch_system(integer(), pos_integer(), pos_integer()) :: fetch_result()
  defp fetch_system(system_id, since_hours, limit) do
    alias WandererKills.External.ZKB
    alias WandererKills.Killmails.Coordinator

    # Check cache first
    case Cache.system_recently_fetched?(system_id) do
      {:ok, true} ->
        # Cache is fresh, get cached data
        case Cache.get_killmails_for_system(system_id) do
          {:ok, killmail_ids} ->
            Logger.debug("Using cached killmails for system",
              system_id: system_id,
              cached_count: length(killmail_ids)
            )

            :ok

          {:error, _reason} ->
            # Cache data missing, fetch from remote
            fetch_remote_killmails(system_id, since_hours, limit)
        end

      {:ok, false} ->
        # Cache is stale, fetch from remote
        fetch_remote_killmails(system_id, since_hours, limit)

      {:error, _reason} ->
        # Cache check failed, fetch from remote
        fetch_remote_killmails(system_id, since_hours, limit)
    end
  end

  defp fetch_remote_killmails(system_id, since_hours, limit) do
    alias WandererKills.External.ZKB
    alias WandererKills.Killmails.Coordinator

    with {:ok, raw_killmails} <- ZKB.fetch_system_killmails(system_id, limit, since_hours),
         {:ok, processed_killmails} <-
           Coordinator.process_killmails(raw_killmails, system_id, since_hours),
         :ok <- cache_killmails_for_system(system_id, processed_killmails) do
      Logger.debug("Successfully fetched killmails for system",
        system_id: system_id,
        killmail_count: length(processed_killmails)
      )

      :ok
    else
      {:error, reason} ->
        Logger.debug("Fetch error for system #{system_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp cache_killmails_for_system(system_id, killmails) when is_list(killmails) do
    try do
      # Update fetch timestamp
      case Cache.set_system_fetch_timestamp(system_id, DateTime.utc_now()) do
        {:ok, :set} -> :ok
        # Continue anyway
        {:error, _reason} -> :ok
      end

      # Extract killmail IDs and cache individual killmails
      killmail_ids =
        Enum.map(killmails, fn killmail ->
          killmail_id = Map.get(killmail, "killmail_id") || Map.get(killmail, "killID")

          if killmail_id do
            # Cache the individual killmail
            Cache.put(:killmails, killmail_id, killmail)
            killmail_id
          else
            nil
          end
        end)
        |> Enum.filter(&(&1 != nil))

      # Add each killmail ID to system's killmail list
      Enum.each(killmail_ids, fn killmail_id ->
        Cache.add_system_killmail(system_id, killmail_id)
      end)

      # Add system to active list
      Cache.add_active_system(system_id)

      :ok
    rescue
      _error -> {:error, :cache_exception}
    end
  end
end
