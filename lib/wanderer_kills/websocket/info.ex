defmodule WandererKills.WebSocket.Info do
  @moduledoc """
  Business logic for WebSocket connection information and configuration.

  This module centralizes WebSocket-related business logic that was
  previously embedded in the WebSocketController.
  """

  alias WandererKillsWeb.Endpoint
  alias WandererKills.SubscriptionManager

  @config %{
    max_systems_per_subscription: 100,
    timeout_seconds: 45,
    rate_limit: "per_connection"
  }

  @doc """
  Get WebSocket connection information for clients.
  """
  @spec get_connection_info(map()) :: map()
  def get_connection_info(conn_info) do
    %{
      websocket_url: build_websocket_url(conn_info),
      protocol: "Phoenix Channels",
      version: "2.0.0",
      channels: %{
        killmails: "killmails:lobby"
      },
      authentication: %{
        required: false,
        type: "none",
        description: "No authentication required for public killmail data"
      },
      limits: @config,
      documentation: %{
        url: "https://github.com/wanderer-industries/wanderer-kills",
        examples: "/examples/websocket_client.ex"
      }
    }
  end

  @doc """
  Get server status information.
  """
  @spec get_server_status() :: map()
  def get_server_status do
    %{
      status: determine_server_status(),
      active_connections: get_active_connection_count(),
      active_subscriptions: get_active_subscription_count(),
      uptime_seconds: get_uptime_seconds(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Get WebSocket configuration limits.
  """
  @spec get_limits() :: map()
  def get_limits, do: @config

  # Private functions

  defp build_websocket_url(%{scheme: scheme, host: host, port: port}) do
    ws_scheme = if scheme == "https", do: "wss", else: "ws"
    ws_port = if port in [80, 443], do: "", else: ":#{port}"
    "#{ws_scheme}://#{host}#{ws_port}/socket"
  end

  defp determine_server_status do
    cond do
      not endpoint_running?() -> "error"
      get_active_connection_count() > 1000 -> "degraded"
      true -> "operational"
    end
  end

  defp get_active_connection_count do
    # In a real implementation, this would query the Phoenix socket transport
    # For now, return a placeholder
    try do
      Registry.count(WandererKills.Registry)
    rescue
      _ -> 0
    end
  end

  defp get_active_subscription_count do
    try do
      SubscriptionManager.list_subscriptions() |> length()
    rescue
      _ -> 0
    end
  end

  defp get_uptime_seconds do
    {total_ms, _since_last} = :erlang.statistics(:wall_clock)
    div(total_ms, 1000)
  end

  defp endpoint_running? do
    Process.whereis(Endpoint) != nil
  end
end
