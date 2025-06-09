defmodule WandererKillsWeb.WebSocketController do
  @moduledoc """
  WebSocket connection information and status endpoints.

  Provides service discovery information about WebSocket connections
  and real-time status monitoring for WebSocket infrastructure.
  """

  use WandererKillsWeb, :controller
  
  alias WandererKills.WebSocket.Info

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
    json(conn, response)
  end

  @doc """
  WebSocket server status.

  Endpoint: GET /websocket/status
  """
  def status(conn, _params) do
    response = Info.get_server_status()
    json(conn, response)
  end

end
