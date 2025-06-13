# lib/wanderer_kills/application.ex

defmodule WandererKills.App.Application do
  @moduledoc """
  OTP Application entry point for WandererKills.

  Supervises:
    1. EtsManager for WebSocket stats tracking
    2. A Task.Supervisor for background jobs
    3. Phoenix.PubSub for event broadcasting
    4. SubscriptionManager for subscription handling
    5. Cachex instance for unified caching
    6. Observability/monitoring processes
    7. Phoenix Endpoint (WandererKillsWeb.Endpoint)
    8. Telemetry.Poller for periodic measurements
    9. RedisQ for real-time killmail streaming (conditionally)
  """

  use Application
  require Logger
  alias WandererKills.Config
  alias WandererKills.Support.SupervisedTask
  import Cachex.Spec

  @impl true
  def start(_type, _args) do
    # 1) Initialize ETS for our unified KillmailStore
    WandererKills.Storage.KillmailStore.init_tables!()

    # 2) Attach telemetry handlers
    WandererKills.Observability.Telemetry.attach_handlers()

    # 3) Build children list
    children =
      ([
         WandererKills.App.EtsManager,
         {Task.Supervisor, name: WandererKills.TaskSupervisor},
         {Phoenix.PubSub, name: WandererKills.PubSub},
         WandererKills.Subscriptions.CharacterIndex,
         WandererKills.Subscriptions.SystemIndex,
         {WandererKills.SubscriptionManager, [pubsub_name: WandererKills.PubSub]},
         WandererKills.RateLimiter,
         WandererKills.HistoricalFetcher
       ] ++
         cache_children() ++
         [
           WandererKills.Observability.ApiTracker,
           WandererKills.Observability.Metrics,
           WandererKills.Observability.Monitoring,
           WandererKills.Observability.WebSocketStats,
           WandererKills.Observability.UnifiedStatus,
           WandererKillsWeb.Endpoint,
           {:telemetry_poller, measurements: telemetry_measurements(), period: :timer.seconds(10)}
         ])
      |> maybe_redisq()

    # 4) Start the supervisor
    opts = [strategy: :one_for_one, name: WandererKills.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("[Application] Supervisor started successfully")
        # Start ship type update asynchronously without blocking
        spawn(fn ->
          Process.sleep(1000)  # Give the system a moment to fully start
          start_ship_type_update()
        end)
        Logger.info("[Application] Application startup completed successfully")
        {:ok, pid}

      error ->
        Logger.error("[Application] Supervisor failed to start: #{inspect(error)}")
        error
    end
  end

  # Create a single Cachex instance with namespace support
  defp cache_children do
    default_ttl_ms = Config.cache().esi_ttl * 1_000

    opts = [
      default_ttl: default_ttl_ms,
      expiration:
        expiration(
          interval: :timer.seconds(60),
          default: default_ttl_ms,
          lazy: true
        ),
      hooks: [
        hook(module: Cachex.Stats)
      ]
    ]

    [
      {Cachex, [:wanderer_cache, opts]}
    ]
  end

  defp telemetry_measurements do
    [
      {WandererKills.Observability.Monitoring, :measure_http_requests, []},
      {WandererKills.Observability.Monitoring, :measure_cache_operations, []},
      {WandererKills.Observability.Monitoring, :measure_fetch_operations, []},
      {WandererKills.Observability.Monitoring, :measure_system_resources, []},
      {WandererKills.Observability.WebSocketStats, :measure_websocket_metrics, []}
    ]
  end

  defp maybe_redisq(children) do
    if Config.start_redisq?() do
      children ++ [WandererKills.RedisQ]
    else
      children
    end
  end

  @spec start_ship_type_update() :: :ok
  defp start_ship_type_update do
    Logger.info("[Application] Starting ship type update task")

    case SupervisedTask.start_child(
      fn ->
        Logger.info("[Application] Ship type update task executing")
        result = case WandererKills.ShipTypes.Updater.update_ship_types() do
          {:error, reason} ->
            Logger.error("Failed to update ship types: #{inspect(reason)}")
            {:error, reason}

          result ->
            Logger.info("Ship type update completed successfully")
            result
        end
        Logger.info("[Application] Ship type update task finished")
        result
      end,
      task_name: "ship_type_update",
      metadata: %{module: __MODULE__}
    ) do
      {:ok, _pid} ->
        Logger.info("[Application] Ship type update task started successfully")
      {:error, reason} ->
        Logger.error("[Application] Failed to start ship type update task: #{inspect(reason)}")
    end

    :ok
  end
end
