# lib/wanderer_kills/application.ex

defmodule WandererKills.App.Application do
  @moduledoc """
  OTP Application entry point for WandererKills.

  Supervises:
    1. A Task.Supervisor for background jobs
    2. Cachex instances for different cache namespaces
    3. The preloader supervisor tree (conditionally)
    4. The HTTP endpoint (Plug.Cowboy)
    5. Observability/monitoring processes
    6. The Telemetry.Poller for periodic measurements
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
         {WandererKills.SubscriptionManager, [pubsub_name: WandererKills.PubSub]}
       ] ++
         cache_children() ++
         [
           WandererKills.Observability.Metrics,
           WandererKills.Observability.Monitoring,
           WandererKills.Observability.WebSocketStats,
           WandererKillsWeb.Endpoint,
           {:telemetry_poller, measurements: telemetry_measurements(), period: :timer.seconds(10)}
         ])
      |> maybe_preloader()
      |> maybe_redisq()

    # 4) Start the supervisor
    opts = [strategy: :one_for_one, name: WandererKills.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        start_ship_type_update()
        {:ok, pid}

      error ->
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

  defp maybe_preloader(children) do
    # Preloader.Supervisor was removed - it was unused dead code
    # The actual preloading is handled by WandererKills.Preloader
    children
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
    SupervisedTask.start_child(
      fn ->
        case WandererKills.ShipTypes.Updater.update_ship_types() do
          {:error, reason} ->
            Logger.error("Failed to update ship types: #{inspect(reason)}")

          _ ->
            :ok
        end
      end,
      task_name: "ship_type_update",
      metadata: %{module: __MODULE__}
    )

    :ok
  end
end
