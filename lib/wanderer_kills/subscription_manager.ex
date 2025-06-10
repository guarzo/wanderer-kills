defmodule WandererKills.SubscriptionManager do
  @moduledoc """
  GenServer that manages kill subscriptions and notifications.

  This module handles:
  - Tracking active subscriptions
  - Managing subscriber notifications via webhooks and PubSub
  - Broadcasting killmail updates to subscribers
  """

  use GenServer
  require Logger
  alias WandererKills.Types
  alias WandererKills.Support.PubSubTopics
  alias WandererKills.Killmails.Preloader
  alias WandererKills.Http.Client, as: HttpClient

  defmodule State do
    @moduledoc false
    defstruct subscriptions: %{},
              websocket_subscriptions: %{},
              pubsub_name: nil

    @type t :: %__MODULE__{
            subscriptions: %{String.t() => map()},
            websocket_subscriptions: %{String.t() => map()},
            pubsub_name: atom()
          }
  end

  @type subscription_id :: String.t()
  @type subscriber_id :: String.t()
  @type system_id :: integer()

  # Client API

  @doc """
  Starts the subscription manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes to killmail updates for specified systems.
  """
  @spec subscribe(subscriber_id(), [system_id()], String.t() | nil) ::
          {:ok, subscription_id()} | {:error, term()}
  def subscribe(subscriber_id, system_ids, callback_url \\ nil) do
    GenServer.call(__MODULE__, {:subscribe, subscriber_id, system_ids, callback_url})
  end

  @doc """
  Unsubscribes from all killmail updates for a subscriber.
  """
  @spec unsubscribe(subscriber_id()) :: :ok | {:error, term()}
  def unsubscribe(subscriber_id) do
    GenServer.call(__MODULE__, {:unsubscribe, subscriber_id})
  end

  @doc """
  Lists all active subscriptions.
  """
  @spec list_subscriptions() :: [Types.subscription()]
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end

  @doc """
  Broadcasts a killmail update to all relevant subscribers asynchronously.
  """
  @spec broadcast_killmail_update_async(system_id(), [Types.killmail()]) :: :ok
  def broadcast_killmail_update_async(system_id, kills) do
    GenServer.cast(__MODULE__, {:broadcast_killmail_update, system_id, kills})
  end

  @doc """
  Broadcasts a killmail count update to all relevant subscribers asynchronously.
  """
  @spec broadcast_killmail_count_update_async(system_id(), integer()) :: :ok
  def broadcast_killmail_count_update_async(system_id, count) do
    GenServer.cast(__MODULE__, {:broadcast_killmail_count_update, system_id, count})
  end

  @doc """
  Add a WebSocket subscription.
  """
  @spec add_websocket_subscription(map()) :: :ok
  def add_websocket_subscription(subscription) do
    GenServer.cast(__MODULE__, {:add_websocket_subscription, subscription})
  end

  @doc """
  Update a WebSocket subscription.
  """
  @spec update_websocket_subscription(String.t(), map()) :: :ok
  def update_websocket_subscription(subscription_id, updates) do
    GenServer.cast(__MODULE__, {:update_websocket_subscription, subscription_id, updates})
  end

  @doc """
  Remove a WebSocket subscription.
  """
  @spec remove_websocket_subscription(String.t()) :: :ok
  def remove_websocket_subscription(subscription_id) do
    GenServer.cast(__MODULE__, {:remove_websocket_subscription, subscription_id})
  end

  @doc """
  Broadcasts a killmail update to all relevant subscribers.

  @deprecated Use broadcast_killmail_update_async/2 instead
  """
  @spec broadcast_killmail_update(system_id(), [Types.killmail()]) :: :ok
  def broadcast_killmail_update(system_id, kills) do
    broadcast_killmail_update_async(system_id, kills)
  end

  @doc """
  Broadcasts a killmail count update to all relevant subscribers.

  @deprecated Use broadcast_killmail_count_update_async/2 instead
  """
  @spec broadcast_killmail_count_update(system_id(), integer()) :: :ok
  def broadcast_killmail_count_update(system_id, count) do
    broadcast_killmail_count_update_async(system_id, count)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    pubsub_name = Keyword.get(opts, :pubsub_name, WandererKills.PubSub)

    state = %State{
      subscriptions: %{},
      websocket_subscriptions: %{},
      pubsub_name: pubsub_name
    }

    Logger.info("SubscriptionManager started", pubsub_name: pubsub_name)
    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, subscriber_id, system_ids, callback_url}, _from, state) do
    case validate_subscription_params(subscriber_id, system_ids, callback_url) do
      :ok ->
        subscription_id = generate_subscription_id(subscriber_id)

        subscription = %{
          subscriber_id: subscriber_id,
          system_ids: system_ids,
          callback_url: callback_url,
          created_at: DateTime.utc_now()
        }

        new_subscriptions = Map.put(state.subscriptions, subscription_id, subscription)
        new_state = %State{state | subscriptions: new_subscriptions}

        Logger.debug("Subscription created",
          subscriber_id: subscriber_id,
          subscription_id: subscription_id,
          system_ids: system_ids,
          has_callback: !is_nil(callback_url)
        )

        # Preload and send recent killmails for the subscribed systems
        Task.start(fn ->
          try do
            preload_kills_for_new_subscriber(subscription, system_ids)
          rescue
            error ->
              Logger.error("Preload task crashed",
                subscriber_id: subscriber_id,
                error: inspect(error),
                stacktrace: Exception.format_stacktrace(__STACKTRACE__)
              )
          catch
            :exit, reason ->
              Logger.error("Preload task exited",
                subscriber_id: subscriber_id,
                reason: inspect(reason)
              )
          end
        end)

        {:reply, {:ok, subscription_id}, new_state}

      {:error, reason} ->
        Logger.warning("Subscription creation failed",
          subscriber_id: subscriber_id,
          reason: reason
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe, subscriber_id}, _from, state) do
    {removed_subscriptions, remaining_subscriptions} =
      Enum.split_with(state.subscriptions, fn {_id, sub} ->
        sub.subscriber_id == subscriber_id
      end)

    if Enum.empty?(removed_subscriptions) do
      Logger.warning("Unsubscribe failed: subscriber not found", subscriber_id: subscriber_id)
      {:reply, {:error, :not_found}, state}
    else
      new_state = %State{state | subscriptions: Map.new(remaining_subscriptions)}
      removed_count = length(removed_subscriptions)

      Logger.debug("Subscription removed",
        subscriber_id: subscriber_id,
        removed_count: removed_count
      )

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_subscriptions, _from, state) do
    subscriptions =
      state.subscriptions
      |> Enum.map(fn {_id, subscription} -> subscription end)

    {:reply, subscriptions, state}
  end

  @impl true
  def handle_cast({:broadcast_killmail_update, system_id, kills}, state) do
    # Find all subscribers interested in this system
    interested_subscriptions =
      state.subscriptions
      |> Enum.filter(fn {_id, sub} -> system_id in sub.system_ids end)

    if Enum.empty?(interested_subscriptions) do
      log_no_subscribers_if_kills_exist(kills, system_id)
    else
      log_broadcast_details(kills, system_id, interested_subscriptions)

      # Broadcast via PubSub
      broadcast_pubsub_update(state.pubsub_name, system_id, kills, :detailed_kill_update)

      # Send webhook notifications
      Task.start(fn ->
        send_webhook_notifications(interested_subscriptions, system_id, kills, :killmail_update)
      end)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast_killmail_count_update, system_id, count}, state) do
    # Find all subscribers interested in this system
    interested_subscriptions =
      state.subscriptions
      |> Enum.filter(fn {_id, sub} -> system_id in sub.system_ids end)

    if not Enum.empty?(interested_subscriptions) do
      # Broadcast via PubSub
      broadcast_pubsub_count_update(state.pubsub_name, system_id, count)

      # Send webhook notifications
      Task.start(fn ->
        send_webhook_count_notifications(interested_subscriptions, system_id, count)
      end)

      Logger.debug("Killmail count update broadcasted",
        system_id: system_id,
        count: count,
        subscriber_count: length(interested_subscriptions)
      )
    end

    {:noreply, state}
  end

  # WebSocket subscription handlers
  @impl true
  def handle_cast({:add_websocket_subscription, subscription}, state) do
    new_websocket_subscriptions =
      Map.put(state.websocket_subscriptions, subscription.id, subscription)

    new_state = %State{state | websocket_subscriptions: new_websocket_subscriptions}

    Logger.debug("WebSocket subscription added",
      subscription_id: subscription.id,
      user_id: subscription.user_id,
      systems_count: length(subscription.systems)
    )

    {:noreply, new_state}
  end

  def handle_cast({:update_websocket_subscription, subscription_id, updates}, state) do
    case Map.get(state.websocket_subscriptions, subscription_id) do
      nil ->
        Logger.warning("Attempted to update non-existent WebSocket subscription",
          subscription_id: subscription_id
        )

        {:noreply, state}

      existing_subscription ->
        updated_subscription = Map.merge(existing_subscription, updates)

        new_websocket_subscriptions =
          Map.put(state.websocket_subscriptions, subscription_id, updated_subscription)

        new_state = %State{state | websocket_subscriptions: new_websocket_subscriptions}

        Logger.debug("WebSocket subscription updated",
          subscription_id: subscription_id,
          updates: Map.keys(updates)
        )

        {:noreply, new_state}
    end
  end

  def handle_cast({:remove_websocket_subscription, subscription_id}, state) do
    case Map.get(state.websocket_subscriptions, subscription_id) do
      nil ->
        Logger.warning("Attempted to remove non-existent WebSocket subscription",
          subscription_id: subscription_id
        )

        {:noreply, state}

      _subscription ->
        new_websocket_subscriptions =
          Map.delete(state.websocket_subscriptions, subscription_id)

        new_state = %State{state | websocket_subscriptions: new_websocket_subscriptions}

        Logger.debug("WebSocket subscription removed",
          subscription_id: subscription_id
        )

        {:noreply, new_state}
    end
  end

  # Private helper functions

  defp validate_subscription_params(subscriber_id, system_ids, callback_url) do
    cond do
      not is_binary(subscriber_id) or String.trim(subscriber_id) == "" ->
        {:error, :invalid_subscriber_id}

      not is_list(system_ids) or Enum.empty?(system_ids) ->
        {:error, :invalid_system_ids}

      not Enum.all?(system_ids, &is_integer/1) ->
        {:error, :invalid_system_ids}

      not is_nil(callback_url) and not is_binary(callback_url) ->
        {:error, :invalid_callback_url}

      true ->
        :ok
    end
  end

  defp generate_subscription_id(subscriber_id) do
    timestamp = System.system_time(:microsecond)

    :crypto.hash(:sha256, "#{subscriber_id}-#{timestamp}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp broadcast_pubsub_update(pubsub_name, system_id, kills, type) do
    timestamp = DateTime.utc_now()

    # Global killmail updates
    Phoenix.PubSub.broadcast(pubsub_name, "zkb:detailed_kills:updated", %{
      type: type,
      solar_system_id: system_id,
      kills: kills,
      timestamp: timestamp
    })

    # System-specific updates
    Phoenix.PubSub.broadcast(pubsub_name, PubSubTopics.system_topic(system_id), %{
      type: type,
      solar_system_id: system_id,
      kills: kills,
      timestamp: timestamp
    })

    Phoenix.PubSub.broadcast(pubsub_name, PubSubTopics.system_detailed_topic(system_id), %{
      type: type,
      solar_system_id: system_id,
      kills: kills,
      timestamp: timestamp
    })
  end

  defp broadcast_pubsub_count_update(pubsub_name, system_id, count) do
    timestamp = DateTime.utc_now()

    # Global killmail count updates
    Phoenix.PubSub.broadcast(pubsub_name, "zkb:kills:updated", %{
      type: :killmail_count_update,
      solar_system_id: system_id,
      kills: count,
      timestamp: timestamp
    })

    # System-specific updates
    Phoenix.PubSub.broadcast(pubsub_name, PubSubTopics.system_topic(system_id), %{
      type: :killmail_count_update,
      solar_system_id: system_id,
      kills: count,
      timestamp: timestamp
    })
  end

  defp send_webhook_notifications(subscriptions, system_id, kills, type) do
    subscriptions
    |> Enum.filter(fn {_id, sub} -> not is_nil(sub.callback_url) end)
    |> Enum.each(fn {_id, sub} ->
      send_webhook_notification(sub, system_id, kills, type)
    end)
  end

  defp send_webhook_count_notifications(subscriptions, system_id, count) do
    subscriptions
    |> Enum.filter(fn {_id, sub} -> not is_nil(sub.callback_url) end)
    |> Enum.each(fn {_id, sub} ->
      send_webhook_count_notification(sub, system_id, count)
    end)
  end

  defp send_webhook_notification(subscription, system_id, kills, type) do
    payload = %{
      type: type,
      data: %{
        solar_system_id: system_id,
        kills: kills,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    payload_size = byte_size(Jason.encode!(payload))

    Logger.debug("📡 WEBHOOK: Sending notification",
      subscriber_id: subscription.subscriber_id,
      system_id: system_id,
      type: type,
      kill_count: length(kills),
      payload_size_bytes: payload_size,
      callback_url: String.slice(subscription.callback_url, 0, 50) <> "..."
    )

    case HttpClient.post(subscription.callback_url, payload) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.debug("📡 WEBHOOK SUCCESS",
          subscriber_id: subscription.subscriber_id,
          status: status,
          kill_count: length(kills),
          type: type
        )

      {:ok, %{status: status}} ->
        Logger.warning("📡 WEBHOOK FAILED",
          subscriber_id: subscription.subscriber_id,
          status: status,
          kill_count: length(kills),
          type: type
        )

      {:error, reason} ->
        Logger.error("📡 WEBHOOK ERROR",
          subscriber_id: subscription.subscriber_id,
          error: inspect(reason),
          kill_count: length(kills),
          type: type
        )
    end
  end

  defp send_webhook_count_notification(subscription, system_id, count) do
    payload = %{
      type: "killmail_count_update",
      data: %{
        solar_system_id: system_id,
        count: count,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    case HttpClient.post(subscription.callback_url, payload) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.debug("Webhook count notification sent successfully",
          subscriber_id: subscription.subscriber_id,
          callback_url: subscription.callback_url,
          status: status
        )

      {:ok, %{status: status}} ->
        Logger.warning("Webhook count notification failed",
          subscriber_id: subscription.subscriber_id,
          callback_url: subscription.callback_url,
          status: status
        )

      {:error, reason} ->
        Logger.error("Webhook count notification error",
          subscriber_id: subscription.subscriber_id,
          callback_url: subscription.callback_url,
          error: inspect(reason)
        )
    end
  end

  # Preload and send recent kills for a new subscriber
  defp preload_kills_for_new_subscriber(subscription, system_ids) do
    Logger.debug("Preloading kills for new subscriber",
      subscriber_id: subscription.subscriber_id,
      system_count: length(system_ids)
    )

    # Fetch recent kills for each system (limit to 24 hours and 5 kills per system to avoid too many ESI calls)
    limit_per_system = 5
    since_hours = 24

    total_kills_sent =
      system_ids
      |> Enum.map(fn system_id ->
        preload_system_kills(subscription, system_id, since_hours, limit_per_system)
      end)
      |> Enum.sum()

    Logger.debug("Preload completed for new subscriber",
      subscriber_id: subscription.subscriber_id,
      total_systems: length(system_ids),
      total_kills_sent: total_kills_sent
    )
  end

  # Preload kills for a specific system and send to subscriber
  defp preload_system_kills(subscription, system_id, since_hours, limit) do
    Logger.debug("🔍 PRELOAD DEBUG: Starting preload for system",
      subscriber_id: subscription.subscriber_id,
      system_id: system_id,
      since_hours: since_hours,
      limit: limit
    )

    kills = Preloader.preload_kills_for_system(system_id, limit, since_hours)
    send_preload_kills_to_subscriber(subscription, system_id, kills)
  end

  # Helper function to send preload kills to subscriber
  defp send_preload_kills_to_subscriber(subscription, system_id, kills) do
    if length(kills) > 0 do
      Preloader.log_preload_summary(
        %{subscriber_id: subscription.subscriber_id},
        system_id,
        kills
      )

      broadcast_preload_kills(subscription, system_id, kills)
      length(kills)
    else
      Logger.debug("🔍 PRELOAD DEBUG: No kills found for system",
        subscriber_id: subscription.subscriber_id,
        system_id: system_id
      )

      0
    end
  end

  # Helper function to log broadcast details (fixing nesting issue)
  defp log_broadcast_details(kills, system_id, interested_subscriptions) do
    if length(kills) > 0 do
      killmail_ids = Enum.map(kills, & &1["killmail_id"])
      kill_times = Preloader.extract_kill_times(kills)
      enriched_count = Preloader.count_enriched_kills(kills)
      subscriber_ids = Enum.map(interested_subscriptions, fn {_id, sub} -> sub.subscriber_id end)

      Logger.debug("🚀 REAL-TIME BROADCAST: Sending kills to subscribers",
        system_id: system_id,
        kill_count: length(kills),
        killmail_ids: killmail_ids,
        enriched_count: enriched_count,
        unenriched_count: length(kills) - enriched_count,
        kill_time_range: "#{List.first(kill_times)} to #{List.last(kill_times)}",
        subscriber_count: length(interested_subscriptions),
        subscriber_ids: subscriber_ids,
        via_pubsub: true,
        via_webhook: true
      )

      log_sample_kill_data(kills)
    end
  end

  # Helper function to log sample kill data
  defp log_sample_kill_data(kills) do
    sample_kill = List.first(kills)

    Logger.debug("🚀 REAL-TIME SAMPLE KILL DATA",
      killmail_id: sample_kill["killmail_id"],
      victim_character: sample_kill["victim"]["character_name"],
      victim_corp: sample_kill["victim"]["corporation_name"],
      attacker_count: length(sample_kill["attackers"] || []),
      solar_system_id: sample_kill["solar_system_id"],
      total_value: sample_kill["total_value"],
      npc_kill: sample_kill["npc"]
    )
  end

  # Helper function to log when no subscribers exist
  defp log_no_subscribers_if_kills_exist(kills, system_id) do
    if length(kills) > 0 do
      Logger.debug("No subscribers for kill update",
        system_id: system_id,
        kill_count: length(kills)
      )
    end
  end

  # Helper function to broadcast preload kills
  defp broadcast_preload_kills(subscription, system_id, kills) do
    # Send via PubSub
    broadcast_pubsub_update(WandererKills.PubSub, system_id, kills, :preload_killmail_update)

    # Send via webhook if configured
    if subscription.callback_url do
      send_webhook_notification(subscription, system_id, kills, :preload_killmail_update)
    end
  end
end
