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
  alias WandererKills.Subscriptions.{WebhookNotifier, Broadcaster, Preloader}

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
  Gets subscription statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
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
  def handle_call({:subscribe, subscriber_id, system_ids, callback_url}, _from, state) do
    case validate_subscription(subscriber_id, system_ids) do
      :ok ->
        subscription_id = generate_subscription_id()

        subscription = %{
          "id" => subscription_id,
          "subscriber_id" => subscriber_id,
          "system_ids" => system_ids,
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
    subscription_ids =
      state.subscriptions
      |> Enum.filter(fn {_id, sub} -> sub["subscriber_id"] == subscriber_id end)
      |> Enum.map(fn {id, _sub} -> id end)

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
      total_subscribed_systems: count_unique_systems(state)
    }

    {:reply, stats, state}
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
    new_state = put_in(state.websocket_subscriptions[subscription_id], subscription)

    Logger.debug("🔌 Added WebSocket subscription",
      subscription_id: subscription_id,
      system_count: length(subscription["system_ids"])
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

        Logger.debug("🔄 Updated WebSocket subscription",
          subscription_id: subscription_id,
          updates: Map.keys(updates)
        )

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:remove_websocket_subscription, subscription_id}, state) do
    new_websocket_subs = Map.delete(state.websocket_subscriptions, subscription_id)
    new_state = %{state | websocket_subscriptions: new_websocket_subs}

    Logger.debug("❌ Removed WebSocket subscription", subscription_id: subscription_id)

    {:noreply, new_state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

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

  defp generate_subscription_id do
    ("sub_" <> :crypto.strong_rand_bytes(16)) |> Base.url_encode64(padding: false)
  end

  defp send_webhook_notifications(subscriptions, system_id, kills) do
    subscriptions
    |> Enum.filter(fn {_id, sub} ->
      system_id in sub["system_ids"] and sub["callback_url"] != nil
    end)
    |> Enum.each(fn {id, sub} ->
      WebhookNotifier.notify_webhook(sub["callback_url"], system_id, kills, id)
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
      |> Enum.flat_map(& &1["system_ids"])

    websocket_systems =
      state.websocket_subscriptions
      |> Map.values()
      |> Enum.flat_map(& &1["system_ids"])

    (http_systems ++ websocket_systems)
    |> Enum.uniq()
    |> length()
  end
end
