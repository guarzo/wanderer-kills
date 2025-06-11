defmodule WandererKillsWeb.WebSocketController do
  @moduledoc """
  WebSocket connection information and status endpoints.

  Provides service discovery information about WebSocket connections
  and real-time status monitoring for WebSocket infrastructure.
  """

  use WandererKillsWeb, :controller

  alias WandererKills.WebSocket.Info

  # Cache for status endpoint
  @status_cache_key :websocket_status_cache
  @status_cache_ttl 30_000

  # Simple in-memory cache using Process dictionary
  defp get_cached_status do
    case Process.get(@status_cache_key) do
      {data, timestamp} when is_integer(timestamp) ->
        if System.monotonic_time(:millisecond) - timestamp < @status_cache_ttl do
          {:ok, data}
        else
          :expired
        end

      _ ->
        :miss
    end
  end

  defp cache_status(data) do
    Process.put(@status_cache_key, {data, System.monotonic_time(:millisecond)})
    data
  end

  @doc """
  WebSocket connection information.

  Endpoint: GET /websocket
  """
  def info(conn, _params) do
    conn_info = %{
      scheme: conn.scheme,
      host: conn.host,
      port: conn.port
    }

    response = Info.get_connection_info(conn_info)

    conn
    |> put_status(200)
    |> json(response)
  end

  @doc """
  WebSocket server status.

  Endpoint: GET /websocket/status
  """
  def status(conn, _params) do
    # Use cache to reduce load when endpoint is polled frequently
    response =
      case get_cached_status() do
        {:ok, data} ->
          data

        _ ->
          Info.get_server_status()
          |> cache_status()
      end

    conn
    |> put_status(200)
    |> json(response)
  end
end
