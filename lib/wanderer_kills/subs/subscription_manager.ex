defmodule WandererKills.Subs.SubscriptionManager do
  @moduledoc """
  Subscription manager using DynamicSupervisor + Registry pattern.

  Uses individual processes for each subscription, providing better
  fault tolerance and isolation than the previous single GenServer approach.

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

  alias WandererKills.Core.Support.Error
  alias WandererKills.Core.Types
  alias WandererKills.Domain.Killmail
  alias WandererKills.Subs.{SubscriptionSupervisor, SubscriptionWorker}
  alias WandererKills.Subs.Subscriptions.{CharacterIndex, SystemIndex}

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
    with :ok <- validate_subscription_attrs(attrs),
         subscription_id <- generate_subscription_id(),
         subscription <- build_subscription(subscription_id, attrs, type),
         {:ok, _pid} <- SubscriptionSupervisor.start_subscription(subscription) do
      log_subscription_created(subscription_id, attrs, type, subscription)
      {:ok, subscription_id}
    else
      {:error, reason} = error ->
        Logger.error("[ERROR] Failed to create subscription", error: inspect(reason))
        error
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
      Logger.info("[INFO] Unsubscribed subscriber",
        subscriber_id: subscriber_id,
        subscriptions_removed: length(subscriptions_to_remove)
      )

      :ok
    else
      failed_count = Enum.count(results, &(&1 != :ok))

      Logger.warning("[WARNING] Partial unsubscribe failure",
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
        Logger.info("[INFO] Removed subscription", subscription_id: subscription_id)
        :ok

      {:error, :not_found} ->
        Logger.debug("[DEBUG] Subscription not found for removal",
          subscription_id: subscription_id
        )

        # Already gone, that's fine
        :ok
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
        victim = Map.get(killmail, :victim) || Map.get(killmail, "victim")
        attackers = Map.get(killmail, :attackers) || Map.get(killmail, "attackers") || []

        victim_id =
          if victim, do: Map.get(victim, :character_id) || Map.get(victim, "character_id")

        attacker_ids =
          Enum.map(attackers, fn attacker ->
            Map.get(attacker, :character_id) || Map.get(attacker, "character_id")
          end)

        [victim_id | attacker_ids]
      end)
      |> Enum.filter(& &1)
      |> Enum.uniq()

    character_subscriptions =
      if Enum.empty?(all_character_ids) do
        []
      else
        CharacterIndex.find_subscriptions_for_entities(all_character_ids)
      end

    # Combine and deduplicate subscription IDs
    all_subscriptions =
      (system_subscriptions ++ character_subscriptions)
      |> Enum.uniq()

    # Send updates to all interested subscriptions
    Enum.each(all_subscriptions, fn subscription_id ->
      SubscriptionWorker.handle_killmail_update(subscription_id, system_id, kills)
    end)

    :ok
  end

  @doc """
  Broadcasts a killmail count update to all relevant subscribers asynchronously.
  """
  @spec broadcast_killmail_count_update_async(system_id(), integer()) :: :ok
  def broadcast_killmail_count_update_async(system_id, count) do
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

  @doc """
  Removes all subscriptions (useful for testing).
  """
  @spec clear_all_subscriptions() :: :ok
  def clear_all_subscriptions do
    # Get all subscriptions and remove them one by one
    subscriptions = list_subscriptions()

    Enum.each(subscriptions, fn subscription ->
      case Map.get(subscription, "id") || Map.get(subscription, :id) do
        nil -> :ok
        id -> remove_subscription(id)
      end
    end)

    :ok
  end

  @doc """
  Adds a WebSocket subscription (compatibility function).
  """
  @spec add_websocket_subscription(map()) :: {:ok, subscription_id()} | {:error, term()}
  def add_websocket_subscription(attrs) do
    Logger.debug(
      "[SubscriptionManager] Adding WebSocket subscription - user_id: #{attrs["user_id"]}"
    )

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
  # Private Functions
  # ============================================================================

  defp validate_subscription_attrs(attrs) do
    cond do
      not is_map(attrs) ->
        {:error, Error.validation_error(:invalid_attrs, "Subscription attributes must be a map")}

      not Map.has_key?(attrs, "subscriber_id") ->
        {:error, Error.validation_error(:missing_subscriber_id, "subscriber_id is required")}

      is_nil(attrs["subscriber_id"]) or attrs["subscriber_id"] == "" ->
        {:error, Error.validation_error(:empty_subscriber_id, "subscriber_id cannot be empty")}

      Map.has_key?(attrs, "system_ids") and not valid_system_ids?(attrs["system_ids"]) ->
        {:error,
         Error.validation_error(:invalid_system_ids, "system_ids must be a list of integers")}

      true ->
        :ok
    end
  end

  defp valid_system_ids?(system_ids) do
    is_list(system_ids) and
      Enum.all?(system_ids, &is_integer/1)
  end

  defp generate_subscription_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp build_subscription(subscription_id, attrs, type) do
    base_subscription = %{
      "id" => subscription_id,
      "subscriber_id" => attrs["subscriber_id"],
      "system_ids" => attrs["system_ids"] || [],
      "character_ids" => attrs["character_ids"] || [],
      "created_at" => DateTime.utc_now()
    }

    case type do
      :webhook ->
        Map.put(base_subscription, "callback_url", attrs["callback_url"])

      :websocket ->
        Map.merge(base_subscription, %{
          "socket_pid" => attrs["socket_pid"],
          "user_id" => attrs["user_id"]
        })
    end
  end

  defp log_subscription_created(subscription_id, attrs, type, subscription) do
    Logger.debug("[DEBUG] New subscription created via add_subscription",
      subscription_id: subscription_id,
      subscriber_id: attrs["subscriber_id"],
      type: type,
      system_count: length(subscription["system_ids"] || []),
      character_count: length(subscription["character_ids"] || [])
    )
  end
end
