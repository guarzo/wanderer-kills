defmodule WandererKillsWeb.Router do
  @moduledoc """
  Phoenix Router for WandererKills API endpoints.

  Replaces the previous Plug.Router implementation with proper Phoenix routing,
  pipelines, and better organization.
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  # Pipelines

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:put_secure_browser_headers)
    plug(WandererKillsWeb.Plugs.RequestId)
    plug(WandererKillsWeb.Plugs.ApiLogger)
  end

  pipeline :infrastructure do
    plug(:accepts, ["json", "text"])
    plug(WandererKillsWeb.Plugs.RequestId)
  end

  # Health and service discovery routes (no versioning needed)
  scope "/", WandererKillsWeb do
    pipe_through(:infrastructure)

    get("/ping", HealthController, :ping)
    get("/health", HealthController, :health)
    get("/status", HealthController, :status)
    get("/metrics", HealthController, :metrics)

    # WebSocket connection info (infrastructure/service discovery)
    get("/websocket", WebSocketController, :info)
    get("/websocket/status", WebSocketController, :status)
  end

  # API v1 routes
  scope "/api/v1", WandererKillsWeb do
    pipe_through(:api)

    # Kill management
    get("/kills/system/:system_id", KillsController, :list)
    post("/kills/systems", KillsController, :bulk)
    get("/kills/cached/:system_id", KillsController, :cached)
    get("/killmail/:killmail_id", KillsController, :show)
    get("/kills/count/:system_id", KillsController, :count)
  end
end
