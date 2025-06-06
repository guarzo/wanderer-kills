# lib/wanderer_kills/application.ex

defmodule WandererKills.Application do
  @moduledoc """
  OTP Application entry point for WandererKills.

  Supervises:
    1. A `Task.Supervisor` for background jobs
    2. The cache supervisor tree
    3. The preloader supervisor tree
    4. The HTTP endpoint (Plug.Cowboy)
    5. A GenServer or process that reports parser stats
    6. The Telemetry.Poller for periodic measurements
  """

  use Application
  require Logger
  alias WandererKills.Infrastructure.Config

  @impl true
  def start(_type, _args) do
    # 1) Attach telemetry handlers before starting measurements
    WandererKills.Observability.Telemetry.attach_handlers()

    # 2) Build the supervision tree
    base_children = [
      {Task.Supervisor, name: WandererKills.TaskSupervisor},
      {Phoenix.PubSub, name: WandererKills.PubSub},
      WandererKills.Killmails.Store,
      # Direct Cachex supervision instead of single-child supervisor
      {Cachex, name: :unified_cache, ttl: Config.cache_ttl(:killmails)},
      WandererKills.Observability.Monitoring,
      {Plug.Cowboy, scheme: :http, plug: WandererKillsWeb.Api, options: [port: Config.port()]},
      {:telemetry_poller,
       measurements: [
         {WandererKills.Observability.Monitoring, :measure_http_requests, []},
         {WandererKills.Observability.Monitoring, :measure_cache_operations, []},
         {WandererKills.Observability.Monitoring, :measure_fetch_operations, []},
         {WandererKills.Observability.Monitoring, :measure_system_resources, []}
       ],
       period: :timer.seconds(10)}
    ]

    # Conditionally add PreloaderSupervisor based on configuration
    children =
      if Config.start_preloader?() do
        base_children ++ [WandererKills.PreloaderSupervisor]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: WandererKills.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Once the supervisor is running, start a one‐off ship‐type update.
        start_ship_type_update()
        {:ok, pid}

      {:error, _} = error ->
        error
    end
  end

  @spec start_ship_type_update() :: :ok
  defp start_ship_type_update do
    Task.start(fn ->
      # First warm the cache with CSV data
      WandererKills.ShipTypes.Info.warm_cache()

      # Then update with fresh ESI data
      result = WandererKills.ShipTypes.Updater.update_ship_types()

      # Log if it was an error.
      if match?({:error, _}, result) do
        Logger.error("Failed to update ship types: #{inspect(result)}")
      end
    end)

    :ok
  end
end
