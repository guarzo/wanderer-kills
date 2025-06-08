defmodule WandererKillsWeb.KillmailChannel do
  @moduledoc """
  Phoenix Channel for real-time killmail subscriptions.

  Allows WebSocket clients to:
  - Subscribe to specific EVE Online systems
  - Receive real-time killmail updates
  - Manage subscriptions dynamically

  ## Usage

  Connect to the WebSocket and join the channel:
  ```javascript
  const socket = new Socket("/socket", {params: {token: "your-api-token"}})
  const channel = socket.channel("killmails:lobby", {systems: [30000142, 30002187]})

  channel.join()
    .receive("ok", resp => console.log("Joined successfully", resp))
    .receive("error", resp => console.log("Unable to join", resp))

  // Listen for killmail updates
  channel.on("killmail_update", payload => {
    console.log("New killmails:", payload.killmails)
  })

  // Add/remove system subscriptions
  channel.push("subscribe_systems", {systems: [30000144]})
  channel.push("unsubscribe_systems", {systems: [30000142]})
  ```
  """

  use WandererKillsWeb, :channel

  require Logger

  alias WandererKills.SubscriptionManager
  alias WandererKills.Config

  @impl true
  def join("killmails:lobby", %{"systems" => systems} = _params, socket) when is_list(systems) do
    case validate_systems(systems) do
      {:ok, valid_systems} ->
        # Register this WebSocket connection as a subscriber
        subscription_id = create_subscription(socket, valid_systems)

        socket =
          socket
          |> assign(:subscription_id, subscription_id)
          |> assign(:subscribed_systems, MapSet.new(valid_systems))

        Logger.info("Client joined killmail channel",
          user_id: socket.assigns.user_id,
          subscription_id: subscription_id,
          systems_count: length(valid_systems),
          systems: valid_systems
        )

        # Subscribe to Phoenix PubSub topics for these systems
        subscribe_to_systems(valid_systems)

        response = %{
          subscription_id: subscription_id,
          subscribed_systems: valid_systems,
          status: "connected"
        }

        {:ok, response, socket}

      {:error, reason} ->
        Logger.warning("Failed to join killmail channel",
          user_id: socket.assigns.user_id,
          reason: reason,
          systems: systems
        )

        {:error, %{reason: reason}}
    end
  end

  def join("killmails:lobby", _params, socket) do
    # Join without initial systems - they can subscribe later
    subscription_id = create_subscription(socket, [])

    socket =
      socket
      |> assign(:subscription_id, subscription_id)
      |> assign(:subscribed_systems, MapSet.new())

    Logger.info("Client joined killmail channel without initial systems",
      user_id: socket.assigns.user_id,
      subscription_id: subscription_id
    )

    response = %{
      subscription_id: subscription_id,
      subscribed_systems: [],
      status: "connected"
    }

    {:ok, response, socket}
  end

  # Handle subscribing to additional systems
  @impl true
  def handle_in("subscribe_systems", %{"systems" => systems}, socket) when is_list(systems) do
    case validate_systems(systems) do
      {:ok, valid_systems} ->
        current_systems = socket.assigns.subscribed_systems
        new_systems = MapSet.difference(MapSet.new(valid_systems), current_systems)

        if MapSet.size(new_systems) > 0 do
          # Subscribe to new PubSub topics
          subscribe_to_systems(MapSet.to_list(new_systems))

          # Update subscription
          all_systems = MapSet.union(current_systems, new_systems)
          update_subscription(socket.assigns.subscription_id, MapSet.to_list(all_systems))

          socket = assign(socket, :subscribed_systems, all_systems)

          Logger.info("Client subscribed to additional systems",
            user_id: socket.assigns.user_id,
            subscription_id: socket.assigns.subscription_id,
            new_systems: MapSet.to_list(new_systems),
            total_systems: MapSet.size(all_systems)
          )

          {:reply, {:ok, %{subscribed_systems: MapSet.to_list(all_systems)}}, socket}
        else
          {:reply, {:ok, %{message: "Already subscribed to all requested systems"}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Handle unsubscribing from systems
  def handle_in("unsubscribe_systems", %{"systems" => systems}, socket) when is_list(systems) do
    case validate_systems(systems) do
      {:ok, valid_systems} ->
        current_systems = socket.assigns.subscribed_systems
        systems_to_remove = MapSet.intersection(current_systems, MapSet.new(valid_systems))

        if MapSet.size(systems_to_remove) > 0 do
          # Unsubscribe from PubSub topics
          unsubscribe_from_systems(MapSet.to_list(systems_to_remove))

          # Update subscription
          remaining_systems = MapSet.difference(current_systems, systems_to_remove)
          update_subscription(socket.assigns.subscription_id, MapSet.to_list(remaining_systems))

          socket = assign(socket, :subscribed_systems, remaining_systems)

          Logger.info("Client unsubscribed from systems",
            user_id: socket.assigns.user_id,
            subscription_id: socket.assigns.subscription_id,
            removed_systems: MapSet.to_list(systems_to_remove),
            remaining_systems: MapSet.size(remaining_systems)
          )

          {:reply, {:ok, %{subscribed_systems: MapSet.to_list(remaining_systems)}}, socket}
        else
          {:reply, {:ok, %{message: "Not subscribed to any of the requested systems"}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Handle getting current subscription status
  def handle_in("get_status", _params, socket) do
    response = %{
      subscription_id: socket.assigns.subscription_id,
      subscribed_systems: MapSet.to_list(socket.assigns.subscribed_systems),
      connected_at: socket.assigns.connected_at,
      user_id: socket.assigns.user_id
    }

    {:reply, {:ok, response}, socket}
  end

  # Handle Phoenix PubSub messages for killmail updates
  @impl true
  def handle_info(
        %{event: "killmail_update", payload: %{system_id: system_id, killmails: killmails}},
        socket
      ) do
    # Only send if we're subscribed to this system
    if MapSet.member?(socket.assigns.subscribed_systems, system_id) do
      push(socket, "killmail_update", %{
        system_id: system_id,
        killmails: killmails,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    end

    {:noreply, socket}
  end

  def handle_info(
        %{event: "kill_count_update", payload: %{system_id: system_id, count: count}},
        socket
      ) do
    # Only send if we're subscribed to this system
    if MapSet.member?(socket.assigns.subscribed_systems, system_id) do
      push(socket, "kill_count_update", %{
        system_id: system_id,
        count: count,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    end

    {:noreply, socket}
  end

  # Clean up when client disconnects
  @impl true
  def terminate(_reason, socket) do
    if subscription_id = socket.assigns[:subscription_id] do
      # Clean up subscription
      remove_subscription(subscription_id)

      Logger.info("Client disconnected from killmail channel",
        user_id: socket.assigns.user_id,
        subscription_id: subscription_id,
        subscribed_systems_count: MapSet.size(socket.assigns.subscribed_systems || MapSet.new())
      )
    end

    :ok
  end

  # Private helper functions

  defp validate_systems(systems) do
    max_systems = Config.validation(:max_subscribed_systems)

    cond do
      length(systems) > max_systems ->
        {:error, "Too many systems (max: #{max_systems})"}

      Enum.all?(systems, &is_integer/1) ->
        valid_systems =
          Enum.filter(systems, &(&1 > 0 and &1 <= Config.validation(:max_system_id)))

        if length(valid_systems) == length(systems) do
          {:ok, Enum.uniq(valid_systems)}
        else
          {:error, "Invalid system IDs"}
        end

      true ->
        {:error, "System IDs must be integers"}
    end
  end

  defp create_subscription(socket, systems) do
    subscription_id = UUID.uuid4()

    # Register with SubscriptionManager (we'll update this to handle WebSockets)
    SubscriptionManager.add_websocket_subscription(%{
      id: subscription_id,
      user_id: socket.assigns.user_id,
      systems: systems,
      socket_pid: self(),
      connected_at: DateTime.utc_now()
    })

    subscription_id
  end

  defp update_subscription(subscription_id, systems) do
    SubscriptionManager.update_websocket_subscription(subscription_id, %{systems: systems})
  end

  defp remove_subscription(subscription_id) do
    SubscriptionManager.remove_websocket_subscription(subscription_id)
  end

  defp subscribe_to_systems(systems) do
    Enum.each(systems, fn system_id ->
      Phoenix.PubSub.subscribe(
        WandererKills.PubSub,
        WandererKills.Support.PubSubTopics.system_topic(system_id)
      )

      Phoenix.PubSub.subscribe(
        WandererKills.PubSub,
        WandererKills.Support.PubSubTopics.system_detailed_topic(system_id)
      )
    end)
  end

  defp unsubscribe_from_systems(systems) do
    Enum.each(systems, fn system_id ->
      Phoenix.PubSub.unsubscribe(
        WandererKills.PubSub,
        WandererKills.Support.PubSubTopics.system_topic(system_id)
      )

      Phoenix.PubSub.unsubscribe(
        WandererKills.PubSub,
        WandererKills.Support.PubSubTopics.system_detailed_topic(system_id)
      )
    end)
  end
end
