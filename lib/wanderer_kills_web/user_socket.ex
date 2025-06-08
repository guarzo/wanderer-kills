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

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, socket} |> assign(:user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(%{"token" => token} = params, socket, _connect_info) do
    case verify_token(token) do
      {:ok, user_id} ->
        Logger.info("WebSocket connection established",
          user_id: user_id,
          params: Map.drop(params, ["token"])
        )

        socket =
          socket
          |> assign(:user_id, user_id)
          |> assign(:connected_at, DateTime.utc_now())

        {:ok, socket}

      {:error, reason} ->
        Logger.warning("WebSocket connection denied", reason: reason, token: token)
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    Logger.warning("WebSocket connection denied: missing token")
    :error
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     WandererKillsWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  # Simple token verification - in production you'd want proper JWT or similar
  defp verify_token(token) do
    case String.length(token) do
      len when len >= 8 ->
        # For demo purposes, use token as user_id
        # In production, decode and verify JWT/signed token
        {:ok, token}

      _ ->
        {:error, :invalid_token}
    end
  end
end
