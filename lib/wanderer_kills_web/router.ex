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
    plug(WandererKillsWeb.Plugs.ApiLogger)
  end

  pipeline :infrastructure do
    plug(:accepts, ["json", "text"])
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

    # Subscription management
    post("/subscriptions", SubscriptionController, :create)
    get("/subscriptions", SubscriptionController, :index)
    get("/subscriptions/stats", SubscriptionController, :stats)
    delete("/subscriptions/:subscriber_id", SubscriptionController, :delete)

    # Catch-all for undefined API routes
    get("/*path", KillsController, :not_found)
    post("/*path", KillsController, :not_found)
    put("/*path", KillsController, :not_found)
    patch("/*path", KillsController, :not_found)
    delete("/*path", KillsController, :not_found)
  end
end
