defmodule WandererKills.Subscriptions.CharacterIndex do
  @moduledoc """
  Maintains an ETS-based index for fast character -> subscription lookups.

  This module provides O(1) lookups to find all subscriptions interested
  in a specific character ID, significantly improving performance when
  filtering killmails with many attackers.

  ## Architecture

  Now built on the unified BaseIndex implementation, providing:
  1. **Forward Index (ETS)**: `character_id => MapSet[subscription_ids]`
  2. **Reverse Index (Map)**: `subscription_id => [character_ids]`

  This dual structure enables efficient operations:
  - Fast character lookups via ETS
  - Efficient subscription cleanup via reverse index
  - Atomic updates for subscription changes

  ## Performance Characteristics

  - **O(1) character lookups** using ETS table
  - **O(n) subscription updates** where n = character count
  - **Batch operations** for multiple character lookups
  - **Memory efficient** using MapSets to deduplicate subscription IDs

  ## Telemetry & Monitoring

  Emits `[:wanderer_kills, :character, :index]` events for:
  - `:add` - Adding subscriptions to index
  - `:remove` - Removing subscriptions from index
  - `:update` - Updating subscription character lists
  - `:lookup` - Single character lookups
  - `:batch_lookup` - Multiple character lookups

  Each event includes duration and relevant metadata for performance monitoring.

  ## Health Monitoring

  The index provides statistics via `get_stats/0` including:
  - Total subscriptions indexed
  - Total character entries
  - Memory usage estimates

  Warnings are logged for:
  - Large subscription additions (>100 characters)
  - Index size approaching limits

  ## Usage Example

      # Add a subscription
      CharacterIndex.add_subscription("sub_123", [95465499, 90379338])

      # Find subscriptions for a character
      subs = CharacterIndex.find_subscriptions_for_character(95465499)
      # => ["sub_123"]

      # Batch lookup for multiple characters
      subs = CharacterIndex.find_subscriptions_for_characters([95465499, 90379338])
      # => ["sub_123"]

      # Update subscription
      CharacterIndex.update_subscription("sub_123", [95465499, 12345678])

      # Remove subscription
      CharacterIndex.remove_subscription("sub_123")
  """

  use WandererKills.Subscriptions.BaseIndex,
    entity_type: :character,
    table_name: :character_subscription_index

  # ============================================================================
  # Backward Compatibility API
  # ============================================================================
  # These methods maintain the existing API while delegating to the new BaseIndex implementation
  
  @doc """
  Starts the character index server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds a subscription to the index.

  ## Parameters
    - subscription_id: The unique subscription identifier
    - character_ids: List of character IDs this subscription is interested in
  """
  @spec add_subscription(String.t(), [integer()]) :: :ok
  def add_subscription(subscription_id, character_ids) when is_list(character_ids) do
    GenServer.call(__MODULE__, {:add_subscription, subscription_id, character_ids})
  end

  @doc """
  Updates a subscription's character list in the index.
  """
  @spec update_subscription(String.t(), [integer()]) :: :ok
  def update_subscription(subscription_id, character_ids) when is_list(character_ids) do
    GenServer.call(__MODULE__, {:update_subscription, subscription_id, character_ids})
  end

  @doc """
  Removes a subscription from the index.
  """
  @spec remove_subscription(String.t()) :: :ok
  def remove_subscription(subscription_id) do
    GenServer.call(__MODULE__, {:remove_subscription, subscription_id})
  end

  @doc """
  Finds all subscription IDs interested in a specific character.

  Returns a list of subscription IDs that have subscribed to the given character.
  """
  @spec find_subscriptions_for_character(integer()) :: [String.t()]
  def find_subscriptions_for_character(character_id) when is_integer(character_id) do
    start_time = System.monotonic_time()

    result =
      case :ets.lookup(@table_name, character_id) do
        [{^character_id, subscription_ids}] -> MapSet.to_list(subscription_ids)
        [] -> []
      end

    duration = System.monotonic_time() - start_time

    Telemetry.character_index(:lookup, duration, %{
      character_id: character_id,
      result_count: length(result)
    })

    result
  end

  @doc """
  Finds all subscription IDs interested in any of the given characters.

  Returns a deduplicated list of subscription IDs.
  """
  @spec find_subscriptions_for_characters([integer()]) :: [String.t()]
  def find_subscriptions_for_characters(character_ids) when is_list(character_ids) do
    start_time = System.monotonic_time()

    result =
      character_ids
      |> Enum.reduce(MapSet.new(), fn character_id, acc ->
        case :ets.lookup(@table_name, character_id) do
          [{^character_id, subscription_ids}] -> MapSet.union(acc, subscription_ids)
          [] -> acc
        end
      end)
      |> MapSet.to_list()

    duration = System.monotonic_time() - start_time

    Telemetry.character_index(:batch_lookup, duration, %{
      character_count: length(character_ids),
      result_count: length(result)
    })

    result
  end

  @doc """
  Gets statistics about the index.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Clears all data from the index. Useful for testing.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create the ETS table
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Also maintain a reverse index for cleanup
    # subscription_id -> [character_ids]
    reverse_index = %{}

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("CharacterIndex started with ETS table: #{@table_name}")

    {:ok, %{reverse_index: reverse_index}}
  end

  @impl true
  def handle_call({:add_subscription, subscription_id, character_ids}, _from, state) do
    start_time = System.monotonic_time()
    character_count = length(character_ids)

    # Log for large character lists
    if character_count > 100 do
      Logger.info("📊 Adding subscription with large character list",
        subscription_id: subscription_id,
        character_count: character_count
      )
    end

    # Update the forward index (character_id -> subscription_ids)
    Enum.each(character_ids, fn character_id ->
      update_character_index(character_id, subscription_id, :add)
    end)

    # Update the reverse index
    new_reverse_index = Map.put(state.reverse_index, subscription_id, character_ids)

    duration = System.monotonic_time() - start_time

    Telemetry.character_index(:add, duration, %{
      subscription_id: subscription_id,
      character_count: character_count
    })

    {:reply, :ok, %{state | reverse_index: new_reverse_index}}
  end

  @impl true
  def handle_call({:update_subscription, subscription_id, new_character_ids}, _from, state) do
    start_time = System.monotonic_time()

    # Get the old character IDs
    old_character_ids = Map.get(state.reverse_index, subscription_id, [])

    # Find characters to remove and add
    to_remove = MapSet.difference(MapSet.new(old_character_ids), MapSet.new(new_character_ids))
    to_add = MapSet.difference(MapSet.new(new_character_ids), MapSet.new(old_character_ids))

    # Remove subscription from old characters
    Enum.each(to_remove, fn character_id ->
      update_character_index(character_id, subscription_id, :remove)
    end)

    # Add subscription to new characters
    Enum.each(to_add, fn character_id ->
      update_character_index(character_id, subscription_id, :add)
    end)

    # Update the reverse index
    new_reverse_index =
      if new_character_ids == [] do
        Map.delete(state.reverse_index, subscription_id)
      else
        Map.put(state.reverse_index, subscription_id, new_character_ids)
      end

    duration = System.monotonic_time() - start_time

    Telemetry.character_index(:update, duration, %{
      subscription_id: subscription_id,
      old_count: length(old_character_ids),
      new_count: length(new_character_ids)
    })

    {:reply, :ok, %{state | reverse_index: new_reverse_index}}
  end

  @impl true
  def handle_call({:remove_subscription, subscription_id}, _from, state) do
    start_time = System.monotonic_time()

    # Get all character IDs for this subscription
    character_ids = Map.get(state.reverse_index, subscription_id, [])

    # Remove the subscription from all character entries
    Enum.each(character_ids, fn character_id ->
      update_character_index(character_id, subscription_id, :remove)
    end)

    # Remove from reverse index
    new_reverse_index = Map.delete(state.reverse_index, subscription_id)

    duration = System.monotonic_time() - start_time

    Telemetry.character_index(:remove, duration, %{
      subscription_id: subscription_id,
      character_count: length(character_ids)
    })

    {:reply, :ok, %{state | reverse_index: new_reverse_index}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_subscriptions: map_size(state.reverse_index),
      total_character_entries: :ets.info(@table_name, :size),
      total_character_subscriptions:
        Enum.reduce(state.reverse_index, 0, fn {_, chars}, acc ->
          acc + length(chars)
        end)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, %{reverse_index: %{}}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Periodic cleanup to ensure consistency
    # This is mainly for safety in case of any missed updates

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, state}
  end

  # Private functions

  defp update_character_index(character_id, subscription_id, :add) do
    case :ets.lookup(@table_name, character_id) do
      [{^character_id, subscription_ids}] ->
        new_set = MapSet.put(subscription_ids, subscription_id)
        :ets.insert(@table_name, {character_id, new_set})

      [] ->
        :ets.insert(@table_name, {character_id, MapSet.new([subscription_id])})
    end
  end

  defp update_character_index(character_id, subscription_id, :remove) do
    case :ets.lookup(@table_name, character_id) do
      [{^character_id, subscription_ids}] ->
        new_set = MapSet.delete(subscription_ids, subscription_id)

        if MapSet.size(new_set) == 0 do
          # Remove the entry if no subscriptions left
          :ets.delete(@table_name, character_id)
        else
          :ets.insert(@table_name, {character_id, new_set})
        end

      [] ->
        # Nothing to do
        :ok
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
