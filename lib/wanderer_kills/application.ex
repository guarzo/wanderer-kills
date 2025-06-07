# lib/wanderer_kills/application.ex

defmodule WandererKills.Application do
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
  alias WandererKills.Infrastructure.Config
  import Cachex.Spec

  @impl true
  def start(_type, _args) do
    # 1) Initialize ETS for our KillStore
    WandererKills.Killmails.Store.init_tables!()

    # 2) Attach telemetry handlers
    WandererKills.Observability.Telemetry.attach_handlers()

    # 3) Build children list
    children =
      ([
         {Task.Supervisor, name: WandererKills.TaskSupervisor},
         {Phoenix.PubSub, name: WandererKills.PubSub}
       ] ++
         cache_children() ++
         [
           WandererKills.Observability.Monitoring,
           {Plug.Cowboy,
            scheme: :http, plug: WandererKillsWeb.Api, options: [port: Config.app().port]},
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
    # Use a reasonable default TTL - we'll set specific TTLs per key when needed
    default_ttl_ms = Config.cache().esi_ttl * 1_000

    opts = [
      default_ttl: default_ttl_ms,
      expiration:
        expiration(
          interval: :timer.seconds(60),
          default: default_ttl_ms,
          lazy: true
        )
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
      {WandererKills.Observability.Monitoring, :measure_system_resources, []}
    ]
  end

  defp maybe_preloader(children) do
    if Config.start_preloader?() do
      children ++ [WandererKills.Preloader.Supervisor]
    else
      children
    end
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
    Task.start(fn ->
      WandererKills.ShipTypes.Info.warm_cache()

      case WandererKills.ShipTypes.Updater.update_ship_types() do
        {:error, reason} ->
          Logger.error("Failed to update ship types: #{inspect(reason)}")

        _ ->
          :ok
      end
    end)

    :ok
  end
end
