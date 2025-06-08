defmodule WandererKills.Preloader do
  @moduledoc """
  Preloader subsystem for killmail data.

  This module contains both the supervisor and worker components for preloading
  killmail data for active systems. The supervisor manages the worker process
  lifecycle, while the worker handles the actual preloading logic.
  """

  defmodule Supervisor do
    @moduledoc """
    Supervisor for the Preloader subsystem.
    Manages the lifecycle of the Preloader and RedisQ processes.
    """

    use Elixir.Supervisor

    # No @impl here, since Supervisor only defines init/1 as a callback.
    def start_link(opts) do
      Elixir.Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    @spec init(any()) ::
            {:ok,
             {%{
                :strategy => :one_for_one,
                :intensity => non_neg_integer(),
                :period => pos_integer(),
                :auto_shutdown => :all_significant | :any_significant | :never
              }, [Elixir.Supervisor.child_spec()]}}
    def init(_opts) do
      # Build children list based on configuration
      children = []

      # Always include preloader worker
      preloader_worker_spec = %{
        id: WandererKills.Preloader.Worker,
        start: {WandererKills.Preloader.Worker, :start_link, [[]]},
        type: :worker,
        restart: :permanent,
        shutdown: 5_000
      }

      children = [preloader_worker_spec | children]

      # RedisQ module was removed during cleanup - no longer needed
      # All RedisQ functionality is handled through the ZKB client now

      # Reverse to maintain proper order
      children = Enum.reverse(children)

      # Supervisor flags with better fault tolerance
      flags = %{
        strategy: :one_for_one,
        # Allow up to 3 restarts
        intensity: 3,
        # Within 60 seconds
        period: 60,
        auto_shutdown: :any_significant
      }

      {:ok, {flags, children}}
    end
  end

  defmodule Worker do
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

    alias WandererKills.Cache.Helper

    @type pass_type :: :quick | :expanded
    @type fetch_result :: :ok | {:error, term()}

    @passes %{
      quick: %{hours: 1, limit: 5},
      expanded: %{hours: 24, limit: 100}
    }

    @default_max_concurrency 2

    ## Public API

    @doc false
    @spec child_spec(keyword()) :: Elixir.Supervisor.child_spec()
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

      case Helper.system_add_active(system_id) do
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

      Logger.info("Preloader initialized - waiting for subscribers")
      {:ok, %{max_concurrency: max_concurrency}}
    end

    @impl true
    def handle_cast(:run_expanded_pass, %{max_concurrency: _max} = state) do
      case Helper.system_get_active_systems() do
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

      # Monitor the task to handle failures
      Process.monitor(task.pid)
      task
    end

    # Perform a preload pass
    defp do_pass(pass_type, max_concurrency) do
      %{hours: hours, limit: limit} = Map.get(@passes, pass_type)

      Logger.info("Starting #{pass_type} preload pass",
        hours: hours,
        limit: limit,
        max_concurrency: max_concurrency
      )

      case Helper.system_get_active_systems() do
        {:ok, systems} when is_list(systems) and length(systems) > 0 ->
          Logger.info("Processing #{length(systems)} active systems")

          # Take only the limit number of systems for this pass
          systems_to_process = Enum.take(systems, limit)

          # Process systems with limited concurrency
          systems_to_process
          |> Task.async_stream(
            fn system_id -> preload_system(system_id, pass_type) end,
            max_concurrency: max_concurrency,
            timeout: 30_000,
            on_timeout: :kill_task
          )
          |> Enum.each(fn
            {:ok, result} ->
              Logger.debug("System preload completed", result: result)

            {:exit, reason} ->
              Logger.warning("System preload task exited", reason: reason)
          end)

          Logger.info("Completed #{pass_type} preload pass")
          :ok

        {:ok, []} ->
          Logger.info("No active systems to preload")
          {:error, :no_active_systems}

        {:error, reason} ->
          Logger.error("Failed to get active systems for preload", reason: reason)
          {:error, reason}
      end
    end

    # Preload data for a specific system
    defp preload_system(system_id, pass_type) do
      Logger.debug("Preloading system",
        system_id: system_id,
        pass_type: pass_type
      )

      # Fetch kills for this system during preload
      case fetch_and_cache_system_kills(system_id, pass_type) do
        {:ok, kills_count} ->
          Logger.debug("System preload successful",
            system_id: system_id,
            kills_count: kills_count
          )

          # Broadcast kill count update after successful preload
          if kills_count > 0 do
            WandererKills.SubscriptionManager.broadcast_kill_count_update(system_id, kills_count)

            Logger.debug("Broadcasted kill count update from preloader",
              system_id: system_id,
              count: kills_count
            )
          end

          {:ok, system_id}

        {:error, reason} ->
          Logger.warning("System preload failed",
            system_id: system_id,
            reason: reason
          )

          {:error, {system_id, reason}}
      end
    end

    # Fetch and cache kills for a system during preload
    defp fetch_and_cache_system_kills(system_id, pass_type) do
      %{hours: hours, limit: limit} = Map.get(@passes, pass_type)

      case WandererKills.Killmails.ZkbClient.fetch_system_killmails(system_id, limit, hours) do
        {:ok, kills} when is_list(kills) ->
          # Cache the kills (extract killmail IDs first)
          killmail_ids =
            Enum.map(kills, fn kill -> Map.get(kill, "killID") || Map.get(kill, "killmail_id") end)
            |> Enum.filter(&(&1 != nil))

          case Helper.system_put_killmails(system_id, killmail_ids) do
            {:ok, _} ->
              Logger.debug("Cached #{length(kills)} kills for system",
                system_id: system_id,
                count: length(kills)
              )

              {:ok, length(kills)}

            {:error, reason} ->
              Logger.warning("Failed to cache kills for system",
                system_id: system_id,
                error: reason
              )

              {:error, reason}
          end

        {:error, reason} ->
          Logger.warning("Failed to fetch kills for system",
            system_id: system_id,
            error: reason
          )

          {:error, reason}
      end
    end
  end
end
