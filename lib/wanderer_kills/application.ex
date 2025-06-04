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

  @impl true
  def start(_type, _args) do
    # 1) Attach telemetry handlers before starting measurements
    WandererKills.Infrastructure.Telemetry.attach_handlers()

    # 2) Build the supervision tree
    base_children = [
      {Task.Supervisor, name: WandererKills.TaskSupervisor},
      WandererKills.Cache.Supervisor,
      WandererKills.Infrastructure.Monitoring,
      {Plug.Cowboy,
       scheme: :http,
       plug: WandererKills.Web.Api,
       options: [port: Application.fetch_env!(:wanderer_kills, :port)]},
      WandererKills.Parser.Stats,
      {:telemetry_poller,
       measurements: [
         {WandererKills.Infrastructure.Telemetry, :count_http_requests, []},
         {WandererKills.Infrastructure.Telemetry, :count_cache_operations, []},
         {WandererKills.Infrastructure.Telemetry, :count_fetch_operations, []}
       ],
       period: :timer.seconds(10)}
    ]

    # Conditionally add PreloaderSupervisor based on configuration
    children =
      if Application.get_env(:wanderer_kills, :start_preloader, true) do
        [WandererKills.PreloaderSupervisor | base_children]
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
      WandererKills.Data.ShipTypeInfo.warm_cache()

      # Then update with fresh ESI data
      result = WandererKills.Data.ShipTypeUpdater.update_ship_types()

      # Log if it was an error.
      if match?({:error, _}, result) do
        Logger.error("Failed to update ship types: #{inspect(result)}")
      end
    end)

    :ok
  end
end
