defmodule WandererKills.Subs.SubscriptionManager do
  @moduledoc """
  Migrated subscription manager that replaces the single GenServer with
  a DynamicSupervisor + Registry pattern for better fault tolerance.

  This module maintains the same API as the original SubscriptionManager
  while using the new architecture internally.
  """

  use GenServer
  require Logger

  alias WandererKills.Subs.SubscriptionManagerV2
  alias WandererKills.Core.Types
  alias WandererKills.Domain.Killmail

  @type subscription_id :: String.t()
  @type subscriber_id :: String.t()
  @type system_id :: integer()

  # ============================================================================
  # Client API - Same as original SubscriptionManager
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
    SubscriptionManagerV2.subscribe(subscriber_id, system_ids, callback_url)
  end

  @doc """
  Adds a subscription with support for both system and character filtering.
  """
  @spec add_subscription(map(), atom()) :: {:ok, subscription_id()} | {:error, term()}
  def add_subscription(attrs, type \\ :webhook) do
    SubscriptionManagerV2.add_subscription(attrs, type)
  end

  @doc """
  Updates an existing subscription.
  """
  @spec update_subscription(subscription_id(), map()) :: :ok | {:error, term()}
  def update_subscription(subscription_id, updates) do
    SubscriptionManagerV2.update_subscription(subscription_id, updates)
  end

  @doc """
  Unsubscribes from all killmail updates for a subscriber.
  """
  @spec unsubscribe(subscriber_id()) :: :ok | {:error, term()}
  def unsubscribe(subscriber_id) do
    SubscriptionManagerV2.unsubscribe(subscriber_id)
  end

  @doc """
  Removes a specific subscription.
  """
  @spec remove_subscription(subscription_id()) :: :ok | {:error, term()}
  def remove_subscription(subscription_id) do
    SubscriptionManagerV2.remove_subscription(subscription_id)
  end

  @doc """
  Removes all subscriptions (useful for testing).
  """
  @spec clear_all_subscriptions() :: :ok
  def clear_all_subscriptions do
    # Get all subscriptions and remove them one by one
    subscriptions = SubscriptionManagerV2.list_subscriptions()
    
    Enum.each(subscriptions, fn subscription ->
      case Map.get(subscription, "id") || Map.get(subscription, :id) do
        nil -> :ok
        id -> remove_subscription(id)
      end
    end)
    
    :ok
  end

  @doc """
  Lists all active subscriptions.
  """
  @spec list_subscriptions() :: [Types.subscription()]
  def list_subscriptions do
    SubscriptionManagerV2.list_subscriptions()
  end

  @doc """
  Gets a specific subscription.
  """
  @spec get_subscription(subscription_id()) :: {:ok, Types.subscription()} | {:error, term()}
  def get_subscription(subscription_id) do
    SubscriptionManagerV2.get_subscription(subscription_id)
  end

  @doc """
  Broadcasts a killmail update to all relevant subscribers asynchronously.
  """
  @spec broadcast_killmail_update_async(system_id(), [Killmail.t()]) :: :ok
  def broadcast_killmail_update_async(system_id, kills) do
    SubscriptionManagerV2.broadcast_killmail_update_async(system_id, kills)
  end

  @doc """
  Broadcasts a killmail count update to all relevant subscribers asynchronously.
  """
  @spec broadcast_killmail_count_update_async(system_id(), integer()) :: :ok
  def broadcast_killmail_count_update_async(system_id, count) do
    SubscriptionManagerV2.broadcast_killmail_count_update_async(system_id, count)
  end

  @doc """
  Gets statistics about the subscription system.
  """
  @spec get_stats() :: {:ok, map()}
  def get_stats do
    {:ok, SubscriptionManagerV2.get_stats()}
  end

  @doc """
  Adds a WebSocket subscription (compatibility function).
  """
  @spec add_websocket_subscription(map()) :: {:ok, subscription_id()} | {:error, term()}
  def add_websocket_subscription(attrs) do
    add_subscription(attrs, :websocket)
  end

  @doc """
  Updates a WebSocket subscription (compatibility function).
  """
  @spec update_websocket_subscription(subscription_id(), map()) :: :ok | {:error, term()}
  def update_websocket_subscription(subscription_id, updates) do
    update_subscription(subscription_id, updates)
  end

  @doc """
  Removes a WebSocket subscription (compatibility function).
  """
  @spec remove_websocket_subscription(subscription_id()) :: :ok | {:error, term()}
  def remove_websocket_subscription(subscription_id) do
    remove_subscription(subscription_id)
  end

  # ============================================================================
  # GenServer Callbacks - Minimal implementation
  # ============================================================================

  @impl true
  def init(opts) do
    Logger.info("SubscriptionManager started (using new DynamicSupervisor architecture)")

    # The actual work is now done by the DynamicSupervisor architecture
    # This GenServer is mainly here for API compatibility
    {:ok, %{opts: opts}}
  end

  # Most calls are delegated to SubscriptionManagerV2, but we keep this
  # for any potential direct GenServer calls
  @impl true
  def handle_call(request, from, state) do
    Logger.warning("Unexpected GenServer call to SubscriptionManager",
      request: inspect(request),
      from: inspect(from)
    )

    {:reply, {:error, :unsupported}, state}
  end

  @impl true
  def handle_cast(request, state) do
    Logger.warning("Unexpected GenServer cast to SubscriptionManager",
      request: inspect(request)
    )

    {:noreply, state}
  end
end
