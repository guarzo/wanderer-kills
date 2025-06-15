defmodule WandererKills.Subs.SubscriptionManagerV2 do
  @moduledoc """
  New subscription manager using DynamicSupervisor + Registry pattern.

  This replaces the single GenServer approach with individual processes
  for each subscription, providing better fault tolerance and isolation.

  ## Architecture

  - `SubscriptionSupervisor` - DynamicSupervisor managing subscription workers
  - `SubscriptionRegistry` - Registry for efficient process lookup
  - `SubscriptionWorker` - Individual GenServer per subscription
  - `SystemIndex` & `CharacterIndex` - Fast entity-to-subscription lookups

  ## Benefits

  - **Crash Isolation**: Individual subscription failures don't affect others
  - **Scalability**: Each subscription can be processed independently
  - **Fault Tolerance**: Failed subscriptions can be restarted individually
  - **Performance**: Parallel processing of subscription updates
  """

  require Logger
  alias WandererKills.Subs.{SubscriptionSupervisor, SubscriptionWorker}
  alias WandererKills.Subs.Subscriptions.{SystemIndex, CharacterIndex}
  alias WandererKills.Core.Types
  alias WandererKills.Domain.Killmail

  @type subscription_id :: String.t()
  @type subscriber_id :: String.t()
  @type system_id :: integer()
  @type character_id :: integer()

  # ============================================================================
  # Client API - Compatibility with original SubscriptionManager
  # ============================================================================

  @doc """
  Subscribes to killmail updates for specified systems.
  """
  @spec subscribe(subscriber_id(), [system_id()], String.t() | nil) ::
          {:ok, subscription_id()} | {:error, term()}
  def subscribe(subscriber_id, system_ids, callback_url \\ nil) do
    attrs = %{
      "subscriber_id" => subscriber_id,
      "system_ids" => system_ids,
      "character_ids" => [],
      "callback_url" => callback_url
    }

    add_subscription(attrs, :webhook)
  end

  @doc """
  Adds a subscription with support for both system and character filtering.
  """
  @spec add_subscription(map(), atom()) :: {:ok, subscription_id()} | {:error, term()}
  def add_subscription(attrs, type \\ :webhook) do
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

        subscription =
          case type do
            :webhook ->
              Map.put(base_subscription, "callback_url", attrs["callback_url"])

            :websocket ->
              Map.merge(base_subscription, %{
                "socket_pid" => attrs["socket_pid"],
                "user_id" => attrs["user_id"]
              })
          end

        case SubscriptionSupervisor.start_subscription(subscription) do
          {:ok, _pid} ->
            Logger.info("📝 New subscription created via add_subscription",
              subscription_id: subscription_id,
              subscriber_id: attrs["subscriber_id"],
              type: type,
              system_ids: subscription["system_ids"],
              character_ids: subscription["character_ids"]
            )

            {:ok, subscription_id}

          {:error, reason} ->
            Logger.error("❌ Failed to create subscription",
              subscription_id: subscription_id,
              error: inspect(reason)
            )

            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates an existing subscription.
  """
  @spec update_subscription(subscription_id(), map()) :: :ok | {:error, term()}
  def update_subscription(subscription_id, updates) do
    SubscriptionWorker.update_subscription(subscription_id, updates)
  end

  @doc """
  Unsubscribes from all killmail updates for a subscriber.
  """
  @spec unsubscribe(subscriber_id()) :: :ok | {:error, term()}
  def unsubscribe(subscriber_id) do
    # Find all subscriptions for this subscriber
    subscriptions_to_remove =
      list_subscriptions()
      |> Enum.filter(fn sub -> sub["subscriber_id"] == subscriber_id end)
      |> Enum.map(fn sub -> sub["id"] end)

    # Stop all subscription workers for this subscriber
    results =
      Enum.map(subscriptions_to_remove, fn subscription_id ->
        SubscriptionSupervisor.stop_subscription(subscription_id)
      end)

    # Check if all were successful
    if Enum.all?(results, &(&1 == :ok)) do
      Logger.info("🗑️ Unsubscribed subscriber",
        subscriber_id: subscriber_id,
        subscriptions_removed: length(subscriptions_to_remove)
      )

      :ok
    else
      failed_count = Enum.count(results, &(&1 != :ok))

      Logger.warning("⚠️ Partial unsubscribe failure",
        subscriber_id: subscriber_id,
        failed_count: failed_count,
        total_count: length(subscriptions_to_remove)
      )

      {:error, :partial_failure}
    end
  end

  @doc """
  Removes a specific subscription.
  """
  @spec remove_subscription(subscription_id()) :: :ok | {:error, term()}
  def remove_subscription(subscription_id) do
    case SubscriptionSupervisor.stop_subscription(subscription_id) do
      :ok ->
        Logger.info("🗑️ Removed subscription", subscription_id: subscription_id)
        :ok

      {:error, :not_found} ->
        Logger.debug("🤷 Subscription not found for removal", subscription_id: subscription_id)
        # Already gone, that's fine
        :ok

      {:error, reason} ->
        Logger.error("❌ Failed to remove subscription",
          subscription_id: subscription_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Lists all active subscriptions.
  """
  @spec list_subscriptions() :: [Types.subscription()]
  def list_subscriptions do
    # Get all subscription workers and fetch their state
    SubscriptionSupervisor.list_subscriptions()
    |> Enum.map(fn subscription_id ->
      case SubscriptionWorker.get_subscription(subscription_id) do
        {:ok, subscription} -> subscription
        {:error, _} -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  @doc """
  Gets a specific subscription.
  """
  @spec get_subscription(subscription_id()) :: {:ok, Types.subscription()} | {:error, term()}
  def get_subscription(subscription_id) do
    SubscriptionWorker.get_subscription(subscription_id)
  end

  @doc """
  Broadcasts a killmail update to all relevant subscribers asynchronously.

  This function determines which subscriptions are interested in the killmails
  and sends them to the appropriate subscription workers.
  """
  @spec broadcast_killmail_update_async(system_id(), [Killmail.t()]) :: :ok
  def broadcast_killmail_update_async(system_id, kills) do
    # Find subscriptions interested in this system
    system_subscriptions = SystemIndex.find_subscriptions_for_entity(system_id)

    # Find subscriptions interested in characters from these kills
    all_character_ids =
      kills
      |> Enum.flat_map(fn killmail ->
        [
          killmail.victim && killmail.victim.character_id
          | Enum.map(killmail.attackers, & &1.character_id)
        ]
      end)
      |> Enum.filter(& &1)
      |> Enum.uniq()

    character_subscriptions =
      if not Enum.empty?(all_character_ids) do
        CharacterIndex.find_subscriptions_for_entities(all_character_ids)
      else
        []
      end

    # Combine and deduplicate subscription IDs
    all_subscriptions =
      (system_subscriptions ++ character_subscriptions)
      |> Enum.uniq()

    # Send updates to all interested subscriptions
    Enum.each(all_subscriptions, fn subscription_id ->
      SubscriptionWorker.handle_killmail_update(subscription_id, system_id, kills)
    end)

    Logger.debug("📡 Broadcast killmail update",
      system_id: system_id,
      killmail_count: length(kills),
      subscription_count: length(all_subscriptions)
    )

    :ok
  end

  @doc """
  Broadcasts a killmail count update to all relevant subscribers asynchronously.
  """
  @spec broadcast_killmail_count_update_async(system_id(), integer()) :: :ok
  def broadcast_killmail_count_update_async(system_id, count) do
    # For now, we'll use the existing broadcaster for count updates
    # since they don't need per-subscription filtering
    alias WandererKills.Subs.Subscriptions.Broadcaster
    Broadcaster.broadcast_killmail_count(system_id, count)
  end

  @doc """
  Gets statistics about the subscription system.
  """
  @spec get_stats() :: map()
  def get_stats do
    base_stats = SubscriptionSupervisor.get_stats()

    system_stats = SystemIndex.get_stats()
    character_stats = CharacterIndex.get_stats()

    Map.merge(base_stats, %{
      system_index: system_stats,
      character_index: character_stats
    })
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp validate_subscription_attrs(attrs) do
    cond do
      not is_map(attrs) ->
        {:error, "Subscription attributes must be a map"}

      not Map.has_key?(attrs, "subscriber_id") ->
        {:error, "subscriber_id is required"}

      is_nil(attrs["subscriber_id"]) or attrs["subscriber_id"] == "" ->
        {:error, "subscriber_id cannot be empty"}

      true ->
        :ok
    end
  end

  defp generate_subscription_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
