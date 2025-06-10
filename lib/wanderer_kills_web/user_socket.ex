defmodule WandererKillsWeb.UserSocket do
  @moduledoc """
  WebSocket socket for real-time killmail subscriptions.

  Allows clients to:
  - Subscribe to specific EVE Online systems
  - Receive real-time killmail updates
  - Manage their subscriptions dynamically

  """

  use Phoenix.Socket

  require Logger

  # Channels
  channel("killmails:*", WandererKillsWeb.KillmailChannel)

  @impl true
  def connect(params, socket, connect_info) do
    anonymous_id = generate_anonymous_id(params)

    client_identifier = get_client_identifier(params)

    socket =
      socket
      |> assign(:user_id, anonymous_id)
      |> assign(:client_identifier, client_identifier)
      |> assign(:connected_at, DateTime.utc_now())
      |> assign(:anonymous, true)
      |> assign(:peer_data, get_peer_data(connect_info))
      |> assign(:user_agent, get_user_agent(connect_info))

    {:ok, socket}
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

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

  defp generate_anonymous_id(params) do
    random_suffix = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    timestamp = System.system_time(:microsecond)

    case get_client_identifier(params) do
      nil ->
        "#{timestamp}_#{random_suffix}"

      client_id ->
        sanitized_id = sanitize_client_identifier(client_id)
        "#{sanitized_id}_#{timestamp}_#{random_suffix}"
    end
  end

  defp get_client_identifier(params) when is_map(params) do
    params["client_id"] || params["client_identifier"] || params["identifier"]
  end

  defp get_client_identifier(_), do: nil

  defp sanitize_client_identifier(identifier) when is_binary(identifier) do
    identifier
    |> String.trim()
    |> String.slice(0, 32)
    |> String.replace(~r/[^a-zA-Z0-9_\-]/, "_")
    |> case do
      "" -> nil
      sanitized -> sanitized
    end
  end

  defp sanitize_client_identifier(_), do: nil
end
