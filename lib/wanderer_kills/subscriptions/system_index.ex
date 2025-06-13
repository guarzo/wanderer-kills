defmodule WandererKills.Subscriptions.SystemIndex do
  @moduledoc """
  Maintains an ETS-based index for fast system -> subscription lookups.

  This module provides O(1) lookups to find all subscriptions interested
  in a specific system ID, maintaining performance parity with character
  subscriptions for high-throughput scenarios.

  ## Architecture

  The index maintains two data structures:
  1. **Forward Index (ETS)**: `system_id => MapSet[subscription_ids]`
  2. **Reverse Index (Map)**: `subscription_id => [system_ids]`

  This dual structure enables efficient operations:
  - Fast system lookups via ETS
  - Efficient subscription cleanup via reverse index
  - Atomic updates for subscription changes

  ## Performance Characteristics

  - **O(1) system lookups** using ETS table
  - **O(n) subscription updates** where n = system count
  - **Batch operations** for multiple system lookups
  - **Memory efficient** using MapSets to deduplicate subscription IDs

  ## Telemetry & Monitoring

  Emits `[:wanderer_kills, :system, :index]` events for:
  - `:add` - Adding subscriptions to index
  - `:remove` - Removing subscriptions from index
  - `:update` - Updating subscription system lists
  - `:lookup` - Single system lookups
  - `:batch_lookup` - Multiple system lookups

  Each event includes duration and relevant metadata for performance monitoring.

  ## Usage Example

      # Add a subscription
      SystemIndex.add_subscription("sub_123", [30000142, 30000144])

      # Find subscriptions for a system
      subs = SystemIndex.find_subscriptions_for_system(30000142)
      # => ["sub_123"]

      # Batch lookup for multiple systems
      subs = SystemIndex.find_subscriptions_for_systems([30000142, 30000144])
      # => ["sub_123"]

      # Update subscription
      SystemIndex.update_subscription("sub_123", [30000142, 30000999])

      # Remove subscription
      SystemIndex.remove_subscription("sub_123")
  """

  use GenServer
  require Logger
  alias WandererKills.Observability.Telemetry

  @table_name :system_subscription_index
  @cleanup_interval :timer.minutes(5)

  # Client API

  @doc """
  Starts the system index server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds a subscription to the index.

  ## Parameters
    - subscription_id: The unique subscription identifier
    - system_ids: List of system IDs this subscription is interested in
  """
  @spec add_subscription(String.t(), [integer()]) :: :ok
  def add_subscription(subscription_id, system_ids) when is_list(system_ids) do
    GenServer.call(__MODULE__, {:add_subscription, subscription_id, system_ids})
  end

  @doc """
  Updates a subscription's system list in the index.
  """
  @spec update_subscription(String.t(), [integer()]) :: :ok
  def update_subscription(subscription_id, system_ids) when is_list(system_ids) do
    GenServer.call(__MODULE__, {:update_subscription, subscription_id, system_ids})
  end

  @doc """
  Removes a subscription from the index.
  """
  @spec remove_subscription(String.t()) :: :ok
  def remove_subscription(subscription_id) do
    GenServer.call(__MODULE__, {:remove_subscription, subscription_id})
  end

  @doc """
  Finds all subscription IDs interested in a specific system.

  Returns a list of subscription IDs that have subscribed to the given system.
  """
  @spec find_subscriptions_for_system(integer()) :: [String.t()]
  def find_subscriptions_for_system(system_id) when is_integer(system_id) do
    start_time = System.monotonic_time()

    result =
      case :ets.lookup(@table_name, system_id) do
        [{^system_id, subscription_ids}] -> MapSet.to_list(subscription_ids)
        [] -> []
      end

    duration = System.monotonic_time() - start_time

    Telemetry.system_index(:lookup, duration, %{
      system_id: system_id,
      result_count: length(result)
    })

    result
  end

  @doc """
  Finds all subscription IDs interested in any of the given systems.

  Returns a deduplicated list of subscription IDs.
  """
  @spec find_subscriptions_for_systems([integer()]) :: [String.t()]
  def find_subscriptions_for_systems(system_ids) when is_list(system_ids) do
    start_time = System.monotonic_time()

    result =
      system_ids
      |> Enum.reduce(MapSet.new(), fn system_id, acc ->
        case :ets.lookup(@table_name, system_id) do
          [{^system_id, subscription_ids}] -> MapSet.union(acc, subscription_ids)
          [] -> acc
        end
      end)
      |> MapSet.to_list()

    duration = System.monotonic_time() - start_time

    Telemetry.system_index(:batch_lookup, duration, %{
      system_count: length(system_ids),
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
    Logger.info("SystemIndex starting...")

    # Create the ETS table for forward index (system_id -> subscription_ids)
    :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)

    # Initialize reverse index (subscription_id -> [system_ids])
    reverse_index = %{}

    Logger.info("SystemIndex started successfully")

    {:ok, %{reverse_index: reverse_index}}
  end

  @impl true
  def handle_call({:add_subscription, subscription_id, system_ids}, _from, state) do
    start_time = System.monotonic_time()
    system_count = length(system_ids)

    # Log for large system lists
    if system_count > 20 do
      Logger.info("📊 Adding subscription with large system list",
        subscription_id: subscription_id,
        system_count: system_count
      )
    end

    # Update the forward index (system_id -> subscription_ids)
    Enum.each(system_ids, fn system_id ->
      update_system_index(system_id, subscription_id, :add)
    end)

    # Update the reverse index
    new_reverse_index = Map.put(state.reverse_index, subscription_id, system_ids)

    duration = System.monotonic_time() - start_time

    Telemetry.system_index(:add, duration, %{
      subscription_id: subscription_id,
      system_count: system_count
    })

    {:reply, :ok, %{state | reverse_index: new_reverse_index}}
  end

  @impl true
  def handle_call({:update_subscription, subscription_id, new_system_ids}, _from, state) do
    start_time = System.monotonic_time()

    # Get the old system IDs
    old_system_ids = Map.get(state.reverse_index, subscription_id, [])

    # Find systems to remove and add
    to_remove = MapSet.difference(MapSet.new(old_system_ids), MapSet.new(new_system_ids))
    to_add = MapSet.difference(MapSet.new(new_system_ids), MapSet.new(old_system_ids))

    # Remove subscription from old systems
    Enum.each(to_remove, fn system_id ->
      update_system_index(system_id, subscription_id, :remove)
    end)

    # Add subscription to new systems
    Enum.each(to_add, fn system_id ->
      update_system_index(system_id, subscription_id, :add)
    end)

    # Update the reverse index
    new_reverse_index =
      if new_system_ids == [] do
        Map.delete(state.reverse_index, subscription_id)
      else
        Map.put(state.reverse_index, subscription_id, new_system_ids)
      end

    duration = System.monotonic_time() - start_time

    Telemetry.system_index(:update, duration, %{
      subscription_id: subscription_id,
      old_count: length(old_system_ids),
      new_count: length(new_system_ids)
    })

    {:reply, :ok, %{state | reverse_index: new_reverse_index}}
  end

  @impl true
  def handle_call({:remove_subscription, subscription_id}, _from, state) do
    start_time = System.monotonic_time()

    # Get all system IDs for this subscription
    system_ids = Map.get(state.reverse_index, subscription_id, [])

    # Remove the subscription from all system entries
    Enum.each(system_ids, fn system_id ->
      update_system_index(system_id, subscription_id, :remove)
    end)

    # Remove from reverse index
    new_reverse_index = Map.delete(state.reverse_index, subscription_id)

    duration = System.monotonic_time() - start_time

    Telemetry.system_index(:remove, duration, %{
      subscription_id: subscription_id,
      system_count: length(system_ids)
    })

    {:reply, :ok, %{state | reverse_index: new_reverse_index}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_subscriptions: map_size(state.reverse_index),
      total_system_entries: :ets.info(@table_name, :size),
      memory_usage_bytes: :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    new_state = %{state | reverse_index: %{}}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Perform periodic cleanup of empty entries
    cleanup_empty_entries()

    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)

    {:noreply, state}
  end

  # Private functions

  defp update_system_index(system_id, subscription_id, action) do
    case :ets.lookup(@table_name, system_id) do
      [{^system_id, existing_subscriptions}] ->
        new_subscriptions =
          case action do
            :add -> MapSet.put(existing_subscriptions, subscription_id)
            :remove -> MapSet.delete(existing_subscriptions, subscription_id)
          end

        if MapSet.size(new_subscriptions) == 0 do
          :ets.delete(@table_name, system_id)
        else
          :ets.insert(@table_name, {system_id, new_subscriptions})
        end

      [] when action == :add ->
        :ets.insert(@table_name, {system_id, MapSet.new([subscription_id])})

      [] when action == :remove ->
        # System not found, nothing to remove
        :ok
    end
  end

  defp cleanup_empty_entries do
    # Remove any entries with empty subscription sets
    # This is a safety measure in case of race conditions
    :ets.foldl(
      fn {system_id, subscription_ids}, acc ->
        if MapSet.size(subscription_ids) == 0 do
          :ets.delete(@table_name, system_id)
        end

        acc
      end,
      :ok,
      @table_name
    )
  end
end
