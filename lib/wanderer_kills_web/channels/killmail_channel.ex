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
  const socket = new Socket("/socket", {})
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
  alias WandererKills.Killmails.Preloader

  alias WandererKills.SubscriptionManager
  alias WandererKills.Config
  alias WandererKills.Observability.WebSocketStats
  alias WandererKills.Support.Error

  @impl true
  def join("killmails:lobby", %{"systems" => systems} = _params, socket) when is_list(systems) do
    join_with_systems(socket, systems)
  end

  def join("killmails:lobby", _params, socket) do
    # Join without initial systems - they can subscribe later
    subscription_id = create_subscription(socket, [])

    socket =
      socket
      |> assign(:subscription_id, subscription_id)
      |> assign(:subscribed_systems, MapSet.new())

    # Track connection
    WebSocketStats.track_connection(:connected, %{
      user_id: socket.assigns.user_id,
      subscription_id: subscription_id,
      initial_systems_count: 0
    })

    Logger.debug("🔌 Client connected and joined killmail channel",
      user_id: socket.assigns.user_id,
      client_identifier: socket.assigns[:client_identifier],
      subscription_id: subscription_id,
      peer_data: socket.assigns.peer_data,
      user_agent: socket.assigns.user_agent,
      initial_systems_count: 0
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

          Logger.debug("📡 Client subscribed to systems",
            user_id: socket.assigns.user_id,
            subscription_id: socket.assigns.subscription_id,
            new_systems_count: MapSet.size(new_systems),
            total_systems_count: MapSet.size(all_systems)
          )

          # Preload recent kills for new systems
          preload_kills_for_systems(socket, MapSet.to_list(new_systems), "subscription")

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

          Logger.debug("📡 Client unsubscribed from systems",
            user_id: socket.assigns.user_id,
            subscription_id: socket.assigns.subscription_id,
            removed_systems_count: MapSet.size(systems_to_remove),
            remaining_systems_count: MapSet.size(remaining_systems)
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

  # Handle preload after join completes
  @impl true
  def handle_info({:after_join, systems}, socket) do
    Logger.debug("📡 Starting preload after join completed",
      user_id: socket.assigns.user_id,
      subscription_id: socket.assigns.subscription_id,
      systems_count: length(systems)
    )

    preload_kills_for_systems(socket, systems, "initial join")
    {:noreply, socket}
  end

  # Handle Phoenix PubSub messages for killmail updates (from SubscriptionManager)
  def handle_info(
        %{
          type: :detailed_kill_update,
          solar_system_id: system_id,
          kills: killmails,
          timestamp: timestamp
        },
        socket
      ) do
    # Only send if we're subscribed to this system
    if MapSet.member?(socket.assigns.subscribed_systems, system_id) do
      Logger.debug("🔥 Forwarding real-time kills to WebSocket client",
        user_id: socket.assigns.user_id,
        system_id: system_id,
        killmail_count: length(killmails),
        timestamp: timestamp
      )

      push(socket, "killmail_update", %{
        system_id: system_id,
        killmails: killmails,
        timestamp: DateTime.to_iso8601(timestamp),
        preload: false
      })

      # Track kills sent to websocket
      WebSocketStats.increment_kills_sent(:realtime, length(killmails))
    end

    {:noreply, socket}
  end

  def handle_info(
        %{
          type: :kill_count_update,
          solar_system_id: system_id,
          kills: count,
          timestamp: timestamp
        },
        socket
      ) do
    # Only send if we're subscribed to this system
    if MapSet.member?(socket.assigns.subscribed_systems, system_id) do
      Logger.debug("📊 Forwarding kill count update to WebSocket client",
        user_id: socket.assigns.user_id,
        system_id: system_id,
        count: count,
        timestamp: timestamp
      )

      push(socket, "kill_count_update", %{
        system_id: system_id,
        count: count,
        timestamp: DateTime.to_iso8601(timestamp)
      })
    end

    {:noreply, socket}
  end

  # Handle any unmatched PubSub messages
  def handle_info(message, socket) do
    Logger.debug("📨 Unhandled PubSub message",
      user_id: socket.assigns.user_id,
      message: inspect(message) |> String.slice(0, 200)
    )

    {:noreply, socket}
  end

  # Clean up when client disconnects
  @impl true
  def terminate(reason, socket) do
    if subscription_id = socket.assigns[:subscription_id] do
      # Track disconnection
      WebSocketStats.track_connection(:disconnected, %{
        user_id: socket.assigns.user_id,
        subscription_id: subscription_id,
        reason: reason
      })

      # Track subscription removal
      subscribed_systems_count = MapSet.size(socket.assigns.subscribed_systems || MapSet.new())

      WebSocketStats.track_subscription(:removed, subscribed_systems_count, %{
        user_id: socket.assigns.user_id,
        subscription_id: subscription_id
      })

      # Clean up subscription
      remove_subscription(subscription_id)

      duration =
        case socket.assigns[:connected_at] do
          nil ->
            "unknown"

          connected_at ->
            DateTime.diff(DateTime.utc_now(), connected_at, :second)
        end

      Logger.info("🚪 Client disconnected from killmail channel",
        user_id: socket.assigns.user_id,
        subscription_id: subscription_id,
        subscribed_systems_count: MapSet.size(socket.assigns.subscribed_systems || MapSet.new()),
        disconnect_reason: reason,
        connection_duration_seconds: duration,
        socket_transport: socket.transport
      )
    else
      Logger.info("🚪 Client disconnected (no active subscription)",
        user_id: socket.assigns[:user_id] || "unknown",
        disconnect_reason: reason,
        socket_transport: socket.transport
      )
    end

    :ok
  end

  # Private helper functions

  # Helper function to handle join with systems
  defp join_with_systems(socket, systems) do
    case validate_systems(systems) do
      {:ok, valid_systems} ->
        # Register this WebSocket connection as a subscriber
        subscription_id = create_subscription(socket, valid_systems)

        # Track subscription creation
        WebSocketStats.track_subscription(:added, length(valid_systems), %{
          user_id: socket.assigns.user_id,
          subscription_id: subscription_id
        })

        # Track connection with initial systems
        WebSocketStats.track_connection(:connected, %{
          user_id: socket.assigns.user_id,
          subscription_id: subscription_id,
          initial_systems_count: length(valid_systems)
        })

        socket =
          socket
          |> assign(:subscription_id, subscription_id)
          |> assign(:subscribed_systems, MapSet.new(valid_systems))

        Logger.debug("🔌 Client connected and joined killmail channel",
          user_id: socket.assigns.user_id,
          client_identifier: socket.assigns[:client_identifier],
          subscription_id: subscription_id,
          peer_data: socket.assigns.peer_data,
          user_agent: socket.assigns.user_agent,
          initial_systems_count: length(valid_systems)
        )

        # Subscribe to Phoenix PubSub topics for these systems
        subscribe_to_systems(valid_systems)

        # Schedule preload after join completes (can't push during join)
        if length(valid_systems) > 0 do
          send(self(), {:after_join, valid_systems})
        end

        response = %{
          subscription_id: subscription_id,
          subscribed_systems: valid_systems,
          status: "connected"
        }

        {:ok, response, socket}

      {:error, reason} ->
        Logger.warning("❌ Failed to join killmail channel",
          user_id: socket.assigns.user_id,
          reason: reason,
          peer_data: socket.assigns.peer_data,
          systems: systems
        )

        {:error, %{reason: Error.to_string(reason)}}
    end
  end

  defp validate_systems(systems) do
    max_systems = Config.validation(:max_subscribed_systems)

    cond do
      length(systems) > max_systems ->
        {:error,
         Error.validation_error(:too_many_systems, "Too many systems (max: #{max_systems})", %{
           max: max_systems,
           provided: length(systems)
         })}

      Enum.all?(systems, &is_integer/1) ->
        valid_systems =
          Enum.filter(systems, &(&1 > 0 and &1 <= Config.validation(:max_system_id)))

        if length(valid_systems) == length(systems) do
          {:ok, Enum.uniq(valid_systems)}
        else
          {:error,
           Error.validation_error(:invalid_system_ids, "Invalid system IDs", %{systems: systems})}
        end

      true ->
        {:error,
         Error.validation_error(:non_integer_system_ids, "System IDs must be integers", %{
           systems: systems
         })}
    end
  end

  defp create_subscription(socket, systems) do
    subscription_id = generate_random_id()

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

  defp preload_kills_for_systems(socket, systems, reason) do
    user_id = socket.assigns.user_id
    subscription_id = socket.assigns.subscription_id
    limit_per_system = 5

    Logger.debug("📡 Preloading kills for WebSocket client",
      user_id: user_id,
      subscription_id: subscription_id,
      systems_count: length(systems),
      reason: reason
    )

    total_kills_sent =
      systems
      |> Enum.map(fn system_id ->
        preload_system_kills_for_websocket(socket, system_id, limit_per_system)
      end)
      |> Enum.sum()

    Logger.debug("📦 Preload completed for WebSocket client",
      user_id: user_id,
      subscription_id: subscription_id,
      total_systems: length(systems),
      total_kills_sent: total_kills_sent,
      reason: reason
    )
  end

  defp preload_system_kills_for_websocket(socket, system_id, limit) do
    Logger.debug("📦 Starting preload for system",
      user_id: socket.assigns.user_id,
      system_id: system_id,
      limit: limit
    )

    # Use the shared preloader
    kills = Preloader.preload_kills_for_system(system_id, limit, 24)

    Logger.debug("📦 Got kills from preload function",
      user_id: socket.assigns.user_id,
      system_id: system_id,
      kills_count: length(kills)
    )

    send_preload_kills_to_websocket(socket, system_id, kills)
  end

  # Removed - now using shared Preloader module

  # Helper function to send preload kills to WebSocket client
  defp send_preload_kills_to_websocket(socket, system_id, kills) when is_list(kills) do
    if length(kills) > 0 do
      killmail_ids = Enum.map(kills, & &1["killmail_id"])
      kill_times = Preloader.extract_kill_times(kills)
      enriched_count = Preloader.count_enriched_kills(kills)

      Logger.debug("📦 Sending preload kills to WebSocket client",
        user_id: socket.assigns.user_id,
        system_id: system_id,
        killmail_count: length(kills),
        killmail_ids: killmail_ids,
        enriched_count: enriched_count,
        unenriched_count: length(kills) - enriched_count,
        kill_time_range:
          if(length(kill_times) > 0,
            do: "#{List.first(kill_times)} to #{List.last(kill_times)}",
            else: "none"
          )
      )

      # Log sample killmails to debug client issues
      sample_kills = Enum.take(kills, 2)

      Enum.each(sample_kills, fn kill ->
        Logger.debug("📦 Sample killmail being sent",
          killmail_id: kill["killmail_id"],
          system_id: system_id,
          has_victim: Map.has_key?(kill, "victim"),
          has_attackers: Map.has_key?(kill, "attackers"),
          has_zkb: Map.has_key?(kill, "zkb"),
          victim_ship: get_in(kill, ["victim", "ship_type_id"]),
          victim_character: get_in(kill, ["victim", "character_id"]),
          attacker_count: length(Map.get(kill, "attackers", [])),
          total_value: get_in(kill, ["zkb", "totalValue"]),
          kill_time: kill["kill_time"],
          available_keys: Map.keys(kill) |> Enum.sort()
        )
      end)

      # Send killmail update to the WebSocket client
      push(socket, "killmail_update", %{
        system_id: system_id,
        killmails: kills,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        preload: true
      })

      # Track kills sent to websocket
      WebSocketStats.increment_kills_sent(:preload, length(kills))

      length(kills)
    else
      Logger.debug("📦 No kills available for preload",
        user_id: socket.assigns.user_id,
        system_id: system_id,
        reason: "no_kills_found"
      )

      0
    end
  end

  # Removed - now using shared Preloader module for these helper functions

  @doc """
  Get websocket statistics - delegated to WebSocketStats GenServer
  """
  def get_stats do
    WebSocketStats.get_stats()
  end

  @doc """
  Reset websocket statistics - delegated to WebSocketStats GenServer
  """
  def reset_stats do
    WebSocketStats.reset_stats()
  end

  # Generate a unique random ID for subscriptions
  # Uses random bytes encoded in URL-safe Base64
  defp generate_random_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
