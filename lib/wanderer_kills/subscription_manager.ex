defmodule WandererKills.SubscriptionManager do
  @moduledoc """
  GenServer that manages kill subscriptions and notifications.

  This module coordinates subscription management, delegating specific
  responsibilities to specialized modules:
  - `Subscriptions.WebhookNotifier` - Handles webhook notifications
  - `Subscriptions.Broadcaster` - Handles PubSub broadcasting
  - `Subscriptions.Preloader` - Handles kill preloading for new subscriptions
  """

  use GenServer
  require Logger
  alias WandererKills.Types
  alias WandererKills.Support.SupervisedTask

  alias WandererKills.Subscriptions.{
    WebhookNotifier,
    Broadcaster,
    Preloader,
    Filter,
    CharacterIndex,
    SystemIndex
  }

  defmodule State do
    @moduledoc false
    defstruct subscriptions: %{},
              websocket_subscriptions: %{}

    @type t :: %__MODULE__{
            subscriptions: %{String.t() => map()},
            websocket_subscriptions: %{String.t() => map()}
          }
  end

  @type subscription_id :: String.t()
  @type subscriber_id :: String.t()
  @type system_id :: integer()
  @type character_id :: integer()

  # ============================================================================
  # Client API
  # ============================================================================

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
  Adds a subscription with support for both system and character filtering.
  """
  @spec add_subscription(map(), atom()) :: {:ok, subscription_id()} | {:error, term()}
  def add_subscription(attrs, type \\ :webhook) do
    GenServer.call(__MODULE__, {:add_subscription, attrs, type})
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
  Add a WebSocket subscription with character filtering support.
  """
  @spec add_websocket_subscription(String.t(), [system_id()], [character_id()], pid()) :: :ok
  def add_websocket_subscription(user_id, system_ids, character_ids, socket_pid) do
    subscription = %{
      "id" => generate_subscription_id_sync(),
      "user_id" => user_id,
      "system_ids" => system_ids,
      "character_ids" => character_ids,
      "socket_pid" => socket_pid,
      "connected_at" => DateTime.utc_now()
    }

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
  Gets subscription statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears all subscriptions. For testing only.
  """
  @spec clear_all_subscriptions() :: :ok
  def clear_all_subscriptions do
    GenServer.call(__MODULE__, :clear_all_subscriptions)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    Logger.info("SubscriptionManager started")

    state = %State{
      subscriptions: %{},
      websocket_subscriptions: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_subscription, attrs, type}, _from, state) do
    case validate_subscription_attrs(attrs) do
      :ok ->
        subscription_id = generate_subscription_id()

        base_subscription = %{
          "id" => subscription_id,
          "subscriber_id" => attrs["subscriber_id"],
          "system_ids" => attrs["system_ids"] || [],
          "character_ids" => attrs["character_ids"] || [],
          "created_at" => DateTime.utc_now()
        }

        {subscription, new_state} =
          case type do
            :webhook ->
              subscription = Map.put(base_subscription, "callback_url", attrs["callback_url"])
              {subscription, put_in(state.subscriptions[subscription_id], subscription)}

            :websocket ->
              subscription =
                Map.merge(base_subscription, %{
                  "socket_pid" => attrs["socket_pid"],
                  "user_id" => attrs["user_id"]
                })

              {subscription, put_in(state.websocket_subscriptions[subscription_id], subscription)}
          end

        Logger.info("📝 New subscription created via add_subscription",
          subscription_id: subscription_id,
          subscriber_id: attrs["subscriber_id"],
          type: type,
          system_count: length(subscription["system_ids"]),
          character_count: length(subscription["character_ids"])
        )

        # Update character index
        update_character_index(subscription_id, subscription["character_ids"], type)

        # Update system index
        update_system_index(subscription_id, subscription["system_ids"])

        # Preload recent kills asynchronously if it's a webhook subscription
        if type == :webhook do
          Preloader.preload_for_subscription(subscription)
        end

        {:reply, {:ok, subscription_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, subscriber_id, system_ids, callback_url}, _from, state) do
    case validate_subscription(subscriber_id, system_ids) do
      :ok ->
        subscription_id = generate_subscription_id()

        subscription = %{
          "id" => subscription_id,
          "subscriber_id" => subscriber_id,
          "system_ids" => system_ids,
          # Default to empty list for backward compatibility
          "character_ids" => [],
          "callback_url" => callback_url,
          "created_at" => DateTime.utc_now()
        }

        new_state = put_in(state.subscriptions[subscription_id], subscription)

        Logger.info("📝 New subscription created",
          subscription_id: subscription_id,
          subscriber_id: subscriber_id,
          system_count: length(system_ids),
          has_webhook: callback_url != nil
        )

        # Preload recent kills asynchronously
        Preloader.preload_for_subscription(subscription)

        {:reply, {:ok, subscription_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe, subscriber_id}, _from, state) do
    # Find all subscriptions for this subscriber
    subscriptions_to_remove =
      state.subscriptions
      |> Enum.filter(fn {_id, sub} -> sub["subscriber_id"] == subscriber_id end)
      |> Enum.map(fn {id, sub} -> {id, sub} end)

    # Remove from character and system indexes
    Enum.each(subscriptions_to_remove, fn {id, sub} ->
      if sub["character_ids"] && sub["character_ids"] != [] do
        CharacterIndex.remove_subscription(id)
      end

      if sub["system_ids"] && sub["system_ids"] != [] do
        SystemIndex.remove_subscription(id)
      end
    end)

    subscription_ids = Enum.map(subscriptions_to_remove, fn {id, _} -> id end)
    new_subscriptions = Map.drop(state.subscriptions, subscription_ids)
    new_state = %{state | subscriptions: new_subscriptions}

    Logger.info("🗑️ Unsubscribed",
      subscriber_id: subscriber_id,
      removed_count: length(subscription_ids)
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_subscriptions, _from, state) do
    subscriptions = Map.values(state.subscriptions)
    {:reply, subscriptions, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      http_subscription_count: map_size(state.subscriptions),
      websocket_subscription_count: map_size(state.websocket_subscriptions),
      total_subscribed_systems: count_unique_systems(state),
      total_subscribed_characters: count_unique_characters(state)
    }

    {:reply, stats, state}
  end

  def handle_call(:clear_all_subscriptions, _from, _state) do
    # Clear all subscription indices
    CharacterIndex.clear()
    SystemIndex.clear()
    
    # Return a fresh state
    new_state = %State{subscriptions: %{}, websocket_subscriptions: %{}}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:broadcast_killmail_update, system_id, kills}, state) do
    # Broadcast to PubSub
    SupervisedTask.start_child(
      fn -> Broadcaster.broadcast_killmail_update(system_id, kills) end,
      task_name: "broadcast_killmail_update",
      metadata: %{system_id: system_id, kill_count: length(kills)}
    )

    # Send webhooks to HTTP subscribers
    SupervisedTask.start_child(
      fn -> send_webhook_notifications(state.subscriptions, system_id, kills) end,
      task_name: "send_webhook_notifications",
      metadata: %{system_id: system_id, kill_count: length(kills)}
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast_killmail_count_update, system_id, count}, state) do
    # Broadcast to PubSub
    SupervisedTask.start_child(
      fn -> Broadcaster.broadcast_killmail_count(system_id, count) end,
      task_name: "broadcast_killmail_count",
      metadata: %{system_id: system_id, count: count}
    )

    # Send webhooks to HTTP subscribers
    SupervisedTask.start_child(
      fn -> send_webhook_count_notifications(state.subscriptions, system_id, count) end,
      task_name: "send_webhook_count_notifications",
      metadata: %{system_id: system_id, count: count}
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:add_websocket_subscription, subscription}, state) do
    subscription_id = subscription["id"]
    # Ensure character_ids exists, default to empty list
    subscription_with_chars = Map.put_new(subscription, "character_ids", [])
    new_state = put_in(state.websocket_subscriptions[subscription_id], subscription_with_chars)

    # Update character index
    if subscription_with_chars["character_ids"] && subscription_with_chars["character_ids"] != [] do
      CharacterIndex.add_subscription(subscription_id, subscription_with_chars["character_ids"])
    end

    # Update system index
    if subscription["system_ids"] && subscription["system_ids"] != [] do
      SystemIndex.add_subscription(subscription_id, subscription["system_ids"])
    end

    Logger.debug("🔌 Added WebSocket subscription",
      subscription_id: subscription_id,
      system_count: length(subscription["system_ids"] || []),
      character_count: length(subscription_with_chars["character_ids"])
    )

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_websocket_subscription, subscription_id, updates}, state) do
    case Map.get(state.websocket_subscriptions, subscription_id) do
      nil ->
        {:noreply, state}

      existing ->
        updated = Map.merge(existing, updates)
        new_state = put_in(state.websocket_subscriptions[subscription_id], updated)

        # Update character index if character_ids changed
        if Map.has_key?(updates, "character_ids") do
          CharacterIndex.update_subscription(subscription_id, updated["character_ids"] || [])
        end

        # Update system index if system_ids changed
        if Map.has_key?(updates, "system_ids") do
          SystemIndex.update_subscription(subscription_id, updated["system_ids"] || [])
        end

        Logger.debug("🔄 Updated WebSocket subscription",
          subscription_id: subscription_id,
          updates: Map.keys(updates)
        )

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:remove_websocket_subscription, subscription_id}, state) do
    # Get subscription before removing to check for character_ids and system_ids
    if subscription = Map.get(state.websocket_subscriptions, subscription_id) do
      # Remove from character index
      if subscription["character_ids"] && subscription["character_ids"] != [] do
        CharacterIndex.remove_subscription(subscription_id)
      end

      # Remove from system index
      if subscription["system_ids"] && subscription["system_ids"] != [] do
        SystemIndex.remove_subscription(subscription_id)
      end
    end

    new_websocket_subs = Map.delete(state.websocket_subscriptions, subscription_id)
    new_state = %{state | websocket_subscriptions: new_websocket_subs}

    Logger.debug("❌ Removed WebSocket subscription", subscription_id: subscription_id)

    {:noreply, new_state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp update_character_index(subscription_id, character_ids, type) do
    if character_ids && character_ids != [] do
      CharacterIndex.add_subscription(subscription_id, character_ids)

      if type == :websocket and length(character_ids) > 0 do
        Logger.info("🎯 Character-based subscription activated",
          subscription_id: subscription_id,
          character_count: length(character_ids),
          type: type
        )
      end
    end
  end

  defp update_system_index(subscription_id, system_ids) do
    if system_ids && system_ids != [] do
      SystemIndex.add_subscription(subscription_id, system_ids)
    end
  end

  defp validate_subscription(subscriber_id, system_ids) do
    cond do
      subscriber_id == nil or subscriber_id == "" ->
        {:error, "Subscriber ID is required"}

      system_ids == nil or system_ids == [] ->
        {:error, "At least one system ID is required"}

      not Enum.all?(system_ids, &is_integer/1) ->
        {:error, "All system IDs must be integers"}

      true ->
        :ok
    end
  end

  defp validate_subscription_attrs(attrs) do
    with :ok <- validate_subscriber_id(attrs["subscriber_id"]),
         :ok <- validate_at_least_one_id_present(attrs),
         :ok <- validate_system_ids(attrs["system_ids"]),
         :ok <- validate_character_ids(attrs["character_ids"]) do
      :ok
    end
  end

  defp validate_subscriber_id(nil), do: {:error, "Subscriber ID is required"}
  defp validate_subscriber_id(""), do: {:error, "Subscriber ID is required"}
  defp validate_subscriber_id(_), do: :ok

  defp validate_at_least_one_id_present(attrs) do
    system_ids_empty = attrs["system_ids"] == nil or attrs["system_ids"] == []
    character_ids_empty = attrs["character_ids"] == nil or attrs["character_ids"] == []

    if system_ids_empty and character_ids_empty do
      {:error, "At least one system ID or character ID is required"}
    else
      :ok
    end
  end

  defp validate_system_ids(nil), do: :ok
  defp validate_system_ids([]), do: :ok

  defp validate_system_ids(system_ids) do
    if Enum.all?(system_ids, &is_integer/1) do
      :ok
    else
      {:error, "All system IDs must be integers"}
    end
  end

  defp validate_character_ids(nil), do: :ok
  defp validate_character_ids([]), do: :ok

  defp validate_character_ids(character_ids) do
    if Enum.all?(character_ids, &is_integer/1) do
      :ok
    else
      {:error, "All character IDs must be integers"}
    end
  end

  defp generate_subscription_id do
    "sub_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  # Public version for use in client API
  defp generate_subscription_id_sync do
    "sub_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  defp send_webhook_notifications(subscriptions, system_id, kills) do
    subscriptions
    |> Enum.filter(fn {_id, sub} ->
      # Must have a callback URL
      # Check if any kill matches the subscription
      sub["callback_url"] != nil and
        Enum.any?(kills, &Filter.matches_subscription?(&1, sub))
    end)
    |> Enum.each(fn {id, sub} ->
      # Filter kills to only those that match this specific subscription
      matching_kills = Filter.filter_killmails(kills, sub)

      if length(matching_kills) > 0 do
        WebhookNotifier.notify_webhook(sub["callback_url"], system_id, matching_kills, id)
      end
    end)
  end

  defp send_webhook_count_notifications(subscriptions, system_id, count) do
    subscriptions
    |> Enum.filter(fn {_id, sub} ->
      system_id in sub["system_ids"] and sub["callback_url"] != nil
    end)
    |> Enum.each(fn {id, sub} ->
      WebhookNotifier.notify_webhook_count(sub["callback_url"], system_id, count, id)
    end)
  end

  defp count_unique_systems(state) do
    http_systems =
      state.subscriptions
      |> Map.values()
      |> Enum.flat_map(fn sub -> sub["system_ids"] || [] end)

    websocket_systems =
      state.websocket_subscriptions
      |> Map.values()
      |> Enum.flat_map(fn sub -> sub["system_ids"] || [] end)

    (http_systems ++ websocket_systems)
    |> Enum.uniq()
    |> length()
  end

  defp count_unique_characters(state) do
    http_characters =
      state.subscriptions
      |> Map.values()
      |> Enum.flat_map(&(&1["character_ids"] || []))

    websocket_characters =
      state.websocket_subscriptions
      |> Map.values()
      |> Enum.flat_map(&(&1["character_ids"] || []))

    (http_characters ++ websocket_characters)
    |> Enum.uniq()
    |> length()
  end
end
