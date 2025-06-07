# lib/wanderer_kills/application.ex

defmodule WandererKills.Application do
  @moduledoc """
  OTP Application entry point for WandererKills.

  Supervises:
    1. A `Task.Supervisor` for background jobs
    2. Cachex instances for different cache namespaces
    3. The preloader supervisor tree
    4. The HTTP endpoint (Plug.Cowboy)
    5. A GenServer or process that reports parser stats
    6. The Telemetry.Poller for periodic measurements
  """

  use Application
  require Logger
  alias WandererKills.Core.Config

  # each tuple is {cache_name, config_key_for_ttl}
  @caches [
    {:esi,          :esi},
    {:ship_types,   :esi},
    {:systems,      :system},
    {:characters,   :esi},
    {:corporations, :esi},
    {:alliances,    :esi},
    {:killmails,    :killmails}
  ]

  @impl true
  def start(_type, _args) do
    # 1) Initialize ETS tables for killmail storage
    WandererKills.KillStore.init_tables!()

    # 2) Attach telemetry handlers
    WandererKills.Observability.Telemetry.attach_handlers()

    # 3) Build the supervision tree
    base_children =
      [
        {Task.Supervisor, name: WandererKills.TaskSupervisor},
        {Phoenix.PubSub,   name: WandererKills.PubSub}
      ] ++
      # Use Cachex.child_spec to avoid internal naming collisions
      Enum.map(@caches, fn {name, config_key} ->
        Cachex.child_spec(
          name,
          default_ttl: Config.cache_ttl(config_key) * 1_000
        )
      end) ++
      [
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

    # Conditionally add PreloaderSupervisor
    children =
      if Config.start_preloader?() do
        base_children ++ [WandererKills.PreloaderSupervisor]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: WandererKills.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        start_ship_type_update()
        {:ok, pid}

      error ->
        error
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
