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

  pipeline :health do
    plug(:accepts, ["json", "text"])
    plug(WandererKillsWeb.Plugs.RequestId)
  end

  # Health and monitoring routes (no versioning needed)
  scope "/", WandererKillsWeb do
    pipe_through(:health)

    get("/ping", HealthController, :ping)
    get("/health", HealthController, :health)
    get("/status", HealthController, :status)
    get("/metrics", HealthController, :metrics)
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

    # Subscription management (HTTP webhooks - deprecated but maintained)
    post("/subscriptions", SubscriptionsController, :create)
    delete("/subscriptions/:subscriber_id", SubscriptionsController, :delete)
    get("/subscriptions", SubscriptionsController, :index)
  end

  # Killfeed API
  scope "/api", WandererKillsWeb do
    pipe_through(:api)

    get("/killfeed", KillfeedController, :poll)
    get("/killfeed/next", KillfeedController, :next)
  end

  # API v2 routes (future WebSocket-only API)
  scope "/api/v2", WandererKillsWeb do
    pipe_through(:api)

    # WebSocket connection info
    get("/websocket", WebSocketController, :info)
    get("/websocket/status", WebSocketController, :status)
  end
end
