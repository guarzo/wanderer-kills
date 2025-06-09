defmodule WandererKillsWeb.UserSocket do
  @moduledoc """
  WebSocket socket for real-time killmail subscriptions.

  Allows clients to:
  - Subscribe to specific EVE Online systems
  - Receive real-time killmail updates
  - Manage their subscriptions dynamically

  No authentication is required - connections are anonymous.
  """

  use Phoenix.Socket

  require Logger

  # Channels
  channel("killmails:*", WandererKillsWeb.KillmailChannel)

  # Allow anonymous connections - no authentication required
  @impl true
  def connect(_params, socket, connect_info) do
    # Generate anonymous user ID based on connection time and process
    anonymous_id = "anon_#{System.system_time(:microsecond)}_#{inspect(self())}"

    # Store connection info for debugging but don't log here
    # Logging will be handled when user joins a channel
    socket =
      socket
      |> assign(:user_id, anonymous_id)
      |> assign(:connected_at, DateTime.utc_now())
      |> assign(:anonymous, true)
      |> assign(:peer_data, get_peer_data(connect_info))
      |> assign(:user_agent, get_user_agent(connect_info))

    {:ok, socket}
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  # For anonymous connections, we use the anonymous_id
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  # Helper functions for connection info
  defp get_peer_data(connect_info) do
    case connect_info do
      %{peer_data: %{address: address, port: port}} ->
        "#{:inet.ntoa(address)}:#{port}"

      _ ->
        "unknown"
    end
  end

  defp get_user_agent(connect_info) do
    case connect_info do
      %{x_headers: headers} ->
        Enum.find_value(headers, "unknown", fn
          {"user-agent", ua} -> ua
          _ -> nil
        end)

      _ ->
        "unknown"
    end
  end
end
