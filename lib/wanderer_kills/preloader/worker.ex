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

  alias WandererKills.Cache.Unified, as: Cache

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
      :ok ->
        Logger.info("Successfully added system to active list",
          system_id: system_id,
          operation: :add_system,
          status: :success
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

    # Only spawn the quick preload if we have active systems
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

  @spec fetch_system(integer(), pos_integer(), pos_integer()) :: fetch_result()
  defp fetch_system(system_id, since_hours, limit) do
    case WandererKills.Fetcher.fetch_killmails_for_system(system_id,
           since_hours: since_hours,
           limit: limit
         ) do
      {:ok, killmails} ->
        Logger.debug("Successfully fetched killmails for system",
          system_id: system_id,
          killmail_count: length(killmails)
        )

        :ok

      {:error, reason} ->
        Logger.debug("Fetch error for system #{system_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
