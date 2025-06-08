defmodule WandererKillsWeb.WebSocketController do
  @moduledoc """
  WebSocket API information and status endpoints.

  Provides information about WebSocket connections and status
  for API v2 which is WebSocket-first.
  """

  use WandererKillsWeb, :controller

  @doc """
  WebSocket connection information.

  Endpoint: GET /api/v2/websocket
  """
  def info(conn, _params) do
    response = %{
      websocket_url: get_websocket_url(conn),
      protocol: "Phoenix Channels",
      version: "2.0.0",
      channels: %{
        killmails: "killmails:lobby"
      },
      authentication: %{
        type: "token",
        parameter: "token",
        description: "Include your API token in the connection parameters"
      },
      limits: %{
        max_systems_per_subscription: 100,
        timeout_seconds: 45,
        rate_limit: "per_connection"
      },
      documentation: %{
        examples_url: "/examples",
        client_libraries: [
          %{language: "JavaScript", library: "phoenix"},
          %{language: "Python", library: "websockets"},
          %{language: "Elixir", library: "phoenix_channels_client"}
        ]
      }
    }

    json(conn, response)
  end

  @doc """
  WebSocket server status.

  Endpoint: GET /api/v2/websocket/status
  """
  def status(conn, _params) do
    response = %{
      status: get_server_status(),
      active_connections: get_active_connections(),
      active_subscriptions: get_active_subscriptions(),
      uptime_seconds: get_uptime_seconds(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    json(conn, response)
  end

  # Private helper functions

  defp get_websocket_url(conn) do
    scheme = if conn.scheme == :https, do: "wss", else: "ws"
    host = conn.host
    port = conn.port

    "#{scheme}://#{host}:#{port}/socket"
  end

  defp get_server_status do
    case Process.whereis(WandererKillsWeb.Endpoint) do
      nil -> "down"
      _pid -> "up"
    end
  end

  defp get_active_connections do
    # This would integrate with Phoenix.PubSub to count active connections
    # For now, return 0
    0
  end

  defp get_active_subscriptions do
    # This would integrate with SubscriptionManager to count WebSocket subscriptions
    # For now, return 0
    0
  end

  defp get_uptime_seconds do
    # This would track actual uptime
    # For now, return a placeholder
    0
  end
end
