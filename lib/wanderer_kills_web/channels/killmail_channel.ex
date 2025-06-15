defmodule WandererKillsWeb.KillmailChannel do
  @moduledoc """
  Phoenix Channel for real-time killmail subscriptions.

  Allows WebSocket clients to:
  - Subscribe to specific EVE Online systems
  - Subscribe to specific character IDs (as victim or attacker)
  - Receive real-time killmail updates
  - Manage subscriptions dynamically

  ## Installation

  ```bash
  npm install phoenix-websocket
  # or
  yarn add phoenix-websocket
  ```

  ## Usage

  Connect to the WebSocket and join the channel:
  ```javascript
  import {Socket} from "phoenix-websocket"

  const socket = new Socket("ws://localhost:4000/socket", {
    params: {client_identifier: "my-app"}
  })
  socket.connect()

  const channel = socket.channel("killmails:lobby", {
    systems: [30000142, 30002187],
    characters: [95465499, 90379338],  // Optional character IDs
    preload: {
      enabled: true,
      since_hours: 24,
      limit_per_system: 100
    }
  })

  channel.join()
    .receive("ok", resp => console.log("Joined successfully", resp))
    .receive("error", resp => console.log("Unable to join", resp))

  // Listen for killmail updates
  channel.on("new_kill", payload => {
    console.log("New killmail:", payload)
  })

  // Add/remove system subscriptions
  channel.push("subscribe_systems", {systems: [30000144]})
  channel.push("unsubscribe_systems", {systems: [30000142]})

  // Add/remove character subscriptions (supports both formats)
  channel.push("subscribe_characters", {characters: [12345678]})
  channel.push("unsubscribe_characters", {characters: [95465499]})

  // Alternative format also supported for backward compatibility
  channel.push("subscribe_characters", {character_ids: [12345678]})
  channel.push("unsubscribe_characters", {character_ids: [95465499]})

  // Get current subscription status
  channel.push("get_status", {})
    .receive("ok", resp => console.log("Current status:", resp))
  ```
  """

  use WandererKillsWeb, :channel

  require Logger
  alias WandererKills.Subs.Preloader

  alias WandererKills.Subs.SubscriptionManager
  alias WandererKills.Core.Observability.WebSocketStats
  alias WandererKills.Core.Support.Error
  alias WandererKills.Subs.Subscriptions.Filter

  @impl true
  def join("killmails:lobby", %{"systems" => systems} = params, socket) when is_list(systems) do
    characters = Map.get(params, "characters", [])
    preload_config = Map.get(params, "preload", %{})
    join_with_filters(socket, systems, characters, preload_config)
  end

  def join("killmails:lobby", %{"characters" => characters} = params, socket)
      when is_list(characters) do
    systems = Map.get(params, "systems", [])
    preload_config = Map.get(params, "preload", %{})
    join_with_filters(socket, systems, characters, preload_config)
  end

  def join("killmails:lobby", params, socket) do
    # Join without initial systems or characters - they can subscribe later
    preload_config = Map.get(params, "preload", %{})
    subscription_id = create_subscription(socket, [], [], preload_config)

    socket =
      socket
      |> assign(:subscription_id, subscription_id)
      |> assign(:subscribed_systems, MapSet.new())
      |> assign(:subscribed_characters, MapSet.new())

    # Track connection
    WebSocketStats.track_connection(:connected, %{
      user_id: socket.assigns.user_id,
      subscription_id: subscription_id,
      initial_systems_count: 0
    })

    Logger.debug("[DEBUG] Client connected and joined killmail channel",
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
      subscribed_characters: [],
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

          updates = %{
            systems: MapSet.to_list(all_systems),
            characters: MapSet.to_list(socket.assigns[:subscribed_characters] || MapSet.new())
          }

          update_subscription(socket.assigns.subscription_id, updates)

          socket = assign(socket, :subscribed_systems, all_systems)

          Logger.debug("[DEBUG] Client subscribed to systems",
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

          updates = %{
            systems: MapSet.to_list(remaining_systems),
            characters: MapSet.to_list(socket.assigns[:subscribed_characters] || MapSet.new())
          }

          update_subscription(socket.assigns.subscription_id, updates)

          socket = assign(socket, :subscribed_systems, remaining_systems)

          Logger.debug("[DEBUG] Client unsubscribed from systems",
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

  # Handle subscribing to characters (also supports "character_ids" for backward compatibility)
  def handle_in("subscribe_characters", %{"character_ids" => characters} = params, socket)
      when is_list(characters) do
    # Rewrite to standard format and delegate
    handle_in("subscribe_characters", Map.put(params, "characters", characters), socket)
  end

  def handle_in("subscribe_characters", %{"characters" => characters}, socket)
      when is_list(characters) do
    case validate_characters(characters) do
      {:ok, valid_characters} ->
        current_characters = socket.assigns[:subscribed_characters] || MapSet.new()
        new_characters = MapSet.difference(MapSet.new(valid_characters), current_characters)

        if MapSet.size(new_characters) > 0 do
          # Update subscription
          all_characters = MapSet.union(current_characters, new_characters)

          updates = %{
            systems: MapSet.to_list(socket.assigns.subscribed_systems),
            characters: MapSet.to_list(all_characters)
          }

          update_subscription(socket.assigns.subscription_id, updates)

          socket = assign(socket, :subscribed_characters, all_characters)

          Logger.debug("[DEBUG] Client subscribed to characters",
            user_id: socket.assigns.user_id,
            subscription_id: socket.assigns.subscription_id,
            new_characters_count: MapSet.size(new_characters),
            total_characters_count: MapSet.size(all_characters)
          )

          {:reply, {:ok, %{subscribed_characters: MapSet.to_list(all_characters)}}, socket}
        else
          {:reply, {:ok, %{message: "Already subscribed to all requested characters"}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Handle unsubscribing from characters (also supports "character_ids" for backward compatibility)
  def handle_in("unsubscribe_characters", %{"character_ids" => characters} = params, socket)
      when is_list(characters) do
    # Rewrite to standard format and delegate
    handle_in("unsubscribe_characters", Map.put(params, "characters", characters), socket)
  end

  def handle_in("unsubscribe_characters", %{"characters" => characters}, socket)
      when is_list(characters) do
    case validate_characters(characters) do
      {:ok, valid_characters} ->
        current_characters = socket.assigns[:subscribed_characters] || MapSet.new()

        characters_to_remove =
          MapSet.intersection(current_characters, MapSet.new(valid_characters))

        if MapSet.size(characters_to_remove) > 0 do
          # Update subscription
          remaining_characters = MapSet.difference(current_characters, characters_to_remove)

          updates = %{
            systems: MapSet.to_list(socket.assigns.subscribed_systems),
            characters: MapSet.to_list(remaining_characters)
          }

          update_subscription(socket.assigns.subscription_id, updates)

          socket = assign(socket, :subscribed_characters, remaining_characters)

          Logger.debug("[DEBUG] Client unsubscribed from characters",
            user_id: socket.assigns.user_id,
            subscription_id: socket.assigns.subscription_id,
            removed_characters_count: MapSet.size(characters_to_remove),
            remaining_characters_count: MapSet.size(remaining_characters)
          )

          {:reply, {:ok, %{subscribed_characters: MapSet.to_list(remaining_characters)}}, socket}
        else
          {:reply, {:ok, %{message: "Not subscribed to any of the requested characters"}}, socket}
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
      subscribed_characters:
        MapSet.to_list(socket.assigns[:subscribed_characters] || MapSet.new()),
      connected_at: socket.assigns.connected_at,
      user_id: socket.assigns.user_id
    }

    {:reply, {:ok, response}, socket}
  end

  # Handle preload after join completes
  @impl true
  def handle_info({:after_join, systems, preload_config}, socket) do
    Logger.debug("[DEBUG] Starting preload after join completed",
      user_id: socket.assigns.user_id,
      subscription_id: socket.assigns.subscription_id,
      systems_count: length(systems)
    )

    # Check if extended preload is requested
    if preload_config["enabled"] != false && map_size(preload_config) > 0 do
      # Request extended historical preload
      case WandererKills.Ingest.HistoricalFetcher.request_preload(
             socket.assigns.subscription_id,
             preload_config
           ) do
        :ok ->
          Logger.info("[INFO] Extended preload requested",
            user_id: socket.assigns.user_id,
            subscription_id: socket.assigns.subscription_id,
            config: preload_config
          )

        {:error, reason} ->
          Logger.error("[ERROR] Failed to request extended preload",
            user_id: socket.assigns.user_id,
            subscription_id: socket.assigns.subscription_id,
            error: reason
          )

          # Fall back to standard preload
          preload_kills_for_systems(socket, systems, "initial join")
      end
    else
      # Standard preload behavior
      preload_kills_for_systems(socket, systems, "initial join")
    end

    {:noreply, socket}
  end

  # Handle legacy after_join without preload config
  def handle_info({:after_join, systems}, socket) do
    Logger.debug("[DEBUG] Starting preload after join completed",
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
    # Build a subscription-like structure for filtering
    subscription = %{
      "system_ids" => MapSet.to_list(socket.assigns.subscribed_systems),
      "character_ids" => MapSet.to_list(socket.assigns[:subscribed_characters] || MapSet.new())
    }

    # Filter killmails based on both system and character subscriptions
    filtered_killmails = Filter.filter_killmails(killmails, subscription)

    if length(filtered_killmails) > 0 do
      Logger.debug("Forwarding real-time kills to WebSocket client",
        user_id: socket.assigns.user_id,
        system_id: system_id,
        original_count: length(killmails),
        filtered_count: length(filtered_killmails),
        timestamp: timestamp
      )

      push(socket, "killmail_update", %{
        system_id: system_id,
        killmails: filtered_killmails,
        timestamp: DateTime.to_iso8601(timestamp),
        preload: false
      })

      # Track kills sent to websocket
      WebSocketStats.increment_kills_sent(:realtime, length(filtered_killmails))
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
      Logger.debug("[DEBUG] Forwarding kill count update to WebSocket client",
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

  # Handle preload status updates from HistoricalFetcher
  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: topic,
          event: "preload_status",
          payload: payload
        },
        socket
      ) do
    if String.ends_with?(topic, socket.assigns.subscription_id) do
      push(socket, "preload_status", payload)
    end

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: topic,
          event: "preload_batch",
          payload: payload
        },
        socket
      ) do
    if String.ends_with?(topic, socket.assigns.subscription_id) do
      push(socket, "preload_batch", payload)

      # Track kills sent
      if payload[:kills] do
        WebSocketStats.increment_kills_sent(:preload, length(payload[:kills]))
      end
    end

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: topic,
          event: "preload_complete",
          payload: payload
        },
        socket
      ) do
    if String.ends_with?(topic, socket.assigns.subscription_id) do
      push(socket, "preload_complete", payload)
    end

    {:noreply, socket}
  end

  # Handle any unmatched PubSub messages
  def handle_info(message, socket) do
    Logger.debug("[DEBUG] Unhandled PubSub message",
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

      Logger.info("[INFO] Client disconnected from killmail channel",
        user_id: socket.assigns.user_id,
        subscription_id: subscription_id,
        subscribed_systems_count: MapSet.size(socket.assigns.subscribed_systems || MapSet.new()),
        disconnect_reason: reason,
        connection_duration_seconds: duration,
        socket_transport: socket.transport
      )
    else
      Logger.info("[INFO] Client disconnected (no active subscription)",
        user_id: socket.assigns[:user_id] || "unknown",
        disconnect_reason: reason,
        socket_transport: socket.transport
      )
    end

    :ok
  end

  # Private helper functions

  # Helper function to handle join with filters
  defp join_with_filters(socket, systems, characters, preload_config) do
    with {:ok, valid_systems} <- validate_systems(systems),
         {:ok, valid_characters} <- validate_characters(characters) do
      # Register this WebSocket connection as a subscriber
      subscription_id =
        create_subscription(socket, valid_systems, valid_characters, preload_config)

      # Track subscription creation
      WebSocketStats.track_subscription(:added, length(valid_systems), %{
        user_id: socket.assigns.user_id,
        subscription_id: subscription_id,
        character_count: length(valid_characters)
      })

      # Track connection with initial systems
      WebSocketStats.track_connection(:connected, %{
        user_id: socket.assigns.user_id,
        subscription_id: subscription_id,
        initial_systems_count: length(valid_systems),
        initial_characters_count: length(valid_characters)
      })

      socket =
        socket
        |> assign(:subscription_id, subscription_id)
        |> assign(:subscribed_systems, MapSet.new(valid_systems))
        |> assign(:subscribed_characters, MapSet.new(valid_characters))
        |> assign(:preload_config, preload_config)

      # Subscribe to the subscription's own topic for preload updates
      Phoenix.PubSub.subscribe(
        WandererKills.PubSub,
        "killmails:#{subscription_id}"
      )

      Logger.debug("[DEBUG] Client connected and joined killmail channel",
        user_id: socket.assigns.user_id,
        client_identifier: socket.assigns[:client_identifier],
        subscription_id: subscription_id,
        peer_data: socket.assigns.peer_data,
        user_agent: socket.assigns.user_agent,
        initial_systems_count: length(valid_systems),
        initial_characters_count: length(valid_characters)
      )

      # Subscribe to Phoenix PubSub topics
      if length(valid_systems) > 0 do
        subscribe_to_systems(valid_systems)
      else
        # If only character subscriptions, subscribe to all_systems topic
        if length(valid_characters) > 0 do
          Phoenix.PubSub.subscribe(
            WandererKills.PubSub,
            WandererKills.Core.Support.PubSubTopics.all_systems_topic()
          )
        end
      end

      # Schedule preload after join completes (can't push during join)
      if length(valid_systems) > 0 do
        send(self(), {:after_join, valid_systems, preload_config})
      end

      response = %{
        subscription_id: subscription_id,
        subscribed_systems: valid_systems,
        subscribed_characters: valid_characters,
        status: "connected"
      }

      {:ok, response, socket}
    else
      {:error, reason} ->
        Logger.warning("[WARNING] Failed to join killmail channel",
          user_id: socket.assigns.user_id,
          reason: reason,
          peer_data: socket.assigns.peer_data,
          systems: systems,
          characters: characters
        )

        {:error, %{reason: Error.to_string(reason)}}
    end
  end

  defp validate_systems(systems) do
    max_systems =
      Application.get_env(:wanderer_kills, :validation, [])
      |> Keyword.get(:max_subscribed_systems, 50)

    max_system_id =
      Application.get_env(:wanderer_kills, :validation, [])
      |> Keyword.get(:max_system_id, 32_000_000)

    cond do
      length(systems) > max_systems ->
        {:error,
         Error.validation_error(:too_many_systems, "Too many systems (max: #{max_systems})", %{
           max: max_systems,
           provided: length(systems)
         })}

      Enum.all?(systems, &is_integer/1) ->
        valid_systems =
          Enum.filter(systems, &(&1 > 0 and &1 <= max_system_id))

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

  defp validate_characters(characters) do
    # Default to 1000 max characters per subscription
    max_characters = 1000

    cond do
      length(characters) > max_characters ->
        {:error,
         Error.validation_error(
           :too_many_characters,
           "Too many characters (max: #{max_characters})",
           %{
             max: max_characters,
             provided: length(characters)
           }
         )}

      Enum.all?(characters, &is_integer/1) ->
        # Character IDs should be positive integers
        valid_characters = Enum.filter(characters, &(&1 > 0))

        if length(valid_characters) == length(characters) do
          {:ok, Enum.uniq(valid_characters)}
        else
          {:error,
           Error.validation_error(:invalid_character_ids, "Invalid character IDs", %{
             characters: characters
           })}
        end

      true ->
        {:error,
         Error.validation_error(:non_integer_character_ids, "Character IDs must be integers", %{
           characters: characters
         })}
    end
  end

  defp create_subscription(socket, systems, characters, preload_config) do
    subscription_id = generate_random_id()

    # Register with SubscriptionManager with character support
    SubscriptionManager.add_websocket_subscription(%{
      "id" => subscription_id,
      "user_id" => socket.assigns.user_id,
      "system_ids" => systems,
      "character_ids" => characters,
      "socket_pid" => self(),
      "connected_at" => DateTime.utc_now(),
      "preload_config" => preload_config
    })

    subscription_id
  end

  defp update_subscription(subscription_id, updates) do
    # Convert atom keys to string keys for consistency
    string_updates =
      updates
      |> Enum.map(fn
        {:systems, value} -> {"system_ids", value}
        {:characters, value} -> {"character_ids", value}
        {key, value} -> {to_string(key), value}
      end)
      |> Enum.into(%{})

    SubscriptionManager.update_websocket_subscription(subscription_id, string_updates)
  end

  defp remove_subscription(subscription_id) do
    SubscriptionManager.remove_websocket_subscription(subscription_id)
  end

  defp subscribe_to_systems(systems) do
    Enum.each(systems, fn system_id ->
      Phoenix.PubSub.subscribe(
        WandererKills.PubSub,
        WandererKills.Core.Support.PubSubTopics.system_topic(system_id)
      )

      Phoenix.PubSub.subscribe(
        WandererKills.PubSub,
        WandererKills.Core.Support.PubSubTopics.system_detailed_topic(system_id)
      )
    end)
  end

  defp unsubscribe_from_systems(systems) do
    Enum.each(systems, fn system_id ->
      Phoenix.PubSub.unsubscribe(
        WandererKills.PubSub,
        WandererKills.Core.Support.PubSubTopics.system_topic(system_id)
      )

      Phoenix.PubSub.unsubscribe(
        WandererKills.PubSub,
        WandererKills.Core.Support.PubSubTopics.system_detailed_topic(system_id)
      )
    end)
  end

  defp preload_kills_for_systems(socket, systems, reason) do
    user_id = socket.assigns.user_id
    subscription_id = socket.assigns.subscription_id
    limit_per_system = 5

    # Count current subscriptions for info logging
    current_systems = MapSet.size(socket.assigns.subscribed_systems)
    current_characters = MapSet.size(socket.assigns[:subscribed_characters] || MapSet.new())

    Logger.info("[INFO] Starting preload for WebSocket client",
      user_id: user_id,
      subscription_id: subscription_id,
      systems_to_preload: length(systems),
      total_subscribed_systems: current_systems,
      total_subscribed_characters: current_characters,
      reason: reason
    )

    # Use SupervisedTask to track WebSocket preload operations
    WandererKills.Core.Support.SupervisedTask.start_child(
      fn ->
        total_kills_sent =
          systems
          |> Enum.map(fn system_id ->
            preload_system_kills_for_websocket(socket, system_id, limit_per_system)
          end)
          |> Enum.sum()

        Logger.info("[INFO] Preload completed for WebSocket client",
          user_id: user_id,
          subscription_id: subscription_id,
          total_systems: length(systems),
          total_kills_sent: total_kills_sent,
          reason: reason
        )

        # Emit telemetry for kills delivered
        :telemetry.execute(
          [:wanderer_kills, :preload, :kills_delivered],
          %{count: total_kills_sent},
          %{user_id: user_id, subscription_id: subscription_id}
        )
      end,
      task_name: "websocket_preload",
      metadata: %{
        user_id: user_id,
        subscription_id: subscription_id,
        systems_count: length(systems),
        reason: reason
      }
    )
  end

  defp preload_system_kills_for_websocket(socket, system_id, limit) do
    Logger.debug("[DEBUG] Starting preload for system",
      user_id: socket.assigns.user_id,
      system_id: system_id,
      limit: limit
    )

    # Use the shared preloader
    kills = Preloader.preload_kills_for_system(system_id, limit, 24)

    Logger.debug("[DEBUG] Got kills from preload function",
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

      Logger.debug("[DEBUG] Sending preload kills to WebSocket client",
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
        Logger.debug("[DEBUG] Sample killmail being sent",
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
      Logger.debug("[DEBUG] No kills available for preload",
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
  @spec get_stats() :: {:ok, map()} | {:error, term()}
  def get_stats do
    WebSocketStats.get_stats()
  end

  @doc """
  Reset websocket statistics - delegated to WebSocketStats GenServer
  """
  @spec reset_stats() :: :ok
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
