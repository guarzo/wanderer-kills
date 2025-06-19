defmodule WandererKills.Subs.Subscriptions.BaseIndex do
  @moduledoc """
  ## Architecture

  The implementation maintains two data structures:
  1. **Forward Index (ETS)**: `entity_id => MapSet[subscription_ids]`
  2. **Reverse Index (Map)**: `subscription_id => [entity_ids]`

  This dual structure enables:
  - O(1) entity lookups via ETS
  - Efficient subscription cleanup via reverse index
  - Atomic updates for subscription changes

  ## Performance Characteristics

  - **O(1) entity lookups** using ETS table
  - **O(n) subscription updates** where n = entity count
  - **Batch operations** for multiple entity lookups
  - **Memory efficient** using MapSets to deduplicate subscription IDs

  ## Telemetry Integration

  Automatically emits telemetry events for performance monitoring:
  - `:add` - Adding subscriptions to index
  - `:remove` - Removing subscriptions from index
  - `:update` - Updating subscription entity lists
  - `:lookup` - Single entity lookups
  - `:batch_lookup` - Multiple entity lookups
  """

  alias WandererKills.Core.Observability.Telemetry

  defmacro __using__(opts) do
    entity_type = Keyword.fetch!(opts, :entity_type)
    entity_type_string = Atom.to_string(entity_type)
    table_name = Keyword.fetch!(opts, :table_name)

    # Generate the module code by combining smaller quote blocks
    [
      generate_module_header(),
      generate_module_attributes(entity_type, entity_type_string, table_name),
      generate_client_api(entity_type),
      generate_server_callbacks(entity_type_string)
    ]
    |> Enum.map(&Macro.expand(&1, __CALLER__))
    |> combine_quoted_expressions()
  end

  # Combines multiple quoted expressions into a single block
  defp combine_quoted_expressions(expressions) do
    quote do
      (unquote_splicing(expressions))
    end
  end

  defp generate_module_header do
    quote do
      use GenServer
      require Logger
      alias WandererKills.Core.Observability.Telemetry
      alias WandererKills.Subs.Subscriptions.BaseIndex
      alias WandererKills.Subs.Subscriptions.IndexBehaviour
      @behaviour IndexBehaviour
    end
  end

  defp generate_module_attributes(entity_type, entity_type_string, table_name) do
    quote do
      @entity_type unquote(entity_type)
      @entity_type_string unquote(entity_type_string)
      @table_name unquote(table_name)
      @cleanup_interval :timer.minutes(5)
    end
  end

  defp generate_client_api(entity_type) do
    quote do
      # ============================================================================
      # Client API
      # ============================================================================

      @doc """
      Starts the #{unquote(entity_type)} index server.
      """
      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @doc """
      Adds a subscription to the #{unquote(entity_type)} index.
      """
      @spec add_subscription(String.t(), [integer()]) :: :ok
      def add_subscription(subscription_id, entity_ids) when is_list(entity_ids) do
        GenServer.call(__MODULE__, {:add_subscription, subscription_id, entity_ids})
      end

      @doc """
      Updates a subscription's #{unquote(entity_type)} list in the index.
      """
      @spec update_subscription(String.t(), [integer()]) :: :ok
      def update_subscription(subscription_id, entity_ids) when is_list(entity_ids) do
        GenServer.call(__MODULE__, {:update_subscription, subscription_id, entity_ids})
      end

      @doc """
      Removes a subscription from the #{unquote(entity_type)} index.
      """
      @spec remove_subscription(String.t()) :: :ok
      def remove_subscription(subscription_id) do
        GenServer.call(__MODULE__, {:remove_subscription, subscription_id})
      end

      @doc """
      Finds all subscription IDs interested in a specific #{unquote(entity_type)}.

      Returns a list of subscription IDs that have subscribed to the given #{unquote(entity_type)}.
      """
      @spec find_subscriptions_for_entity(integer()) :: [String.t()]
      def find_subscriptions_for_entity(entity_id) when is_integer(entity_id) do
        BaseIndex.find_subscriptions_for_entity(
          @table_name,
          entity_id,
          @entity_type
        )
      end

      @doc """
      Finds all subscription IDs interested in any of the given #{unquote(entity_type)}s.

      Returns a deduplicated list of subscription IDs.
      """
      @spec find_subscriptions_for_entities([integer()]) :: [String.t()]
      def find_subscriptions_for_entities(entity_ids) when is_list(entity_ids) do
        BaseIndex.find_subscriptions_for_entities(
          @table_name,
          entity_ids,
          @entity_type
        )
      end

      @doc """
      Gets statistics about the #{unquote(entity_type)} index.
      """
      @spec get_stats() :: map()
      def get_stats do
        GenServer.call(__MODULE__, :get_stats)
      end

      @doc """
      Clears all data from the #{unquote(entity_type)} index. Useful for testing.
      """
      @spec clear() :: :ok
      def clear do
        GenServer.call(__MODULE__, :clear)
      end
    end
  end

  defp generate_server_callbacks(_entity_type_string) do
    quote do
      # ============================================================================
      # Server Callbacks
      # ============================================================================

      @impl true
      def init(_opts) do
        require Logger
        Logger.info("#{String.capitalize(@entity_type_string)}Index starting...")

        # Standardized ETS configuration with both read and write concurrency
        :ets.new(@table_name, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

        # Schedule periodic cleanup
        Process.send_after(self(), :cleanup, @cleanup_interval)

        # Initialize reverse index (subscription_id -> [entity_ids])
        reverse_index = %{}

        Logger.info("#{String.capitalize(@entity_type_string)}Index started successfully")
        {:ok, %{reverse_index: reverse_index}}
      end

      @impl true
      def handle_call({:add_subscription, subscription_id, entity_ids}, _from, state) do
        BaseIndex.handle_add_subscription(
          @table_name,
          @entity_type,
          @entity_type_string,
          subscription_id,
          entity_ids,
          state
        )
      end

      @impl true
      def handle_call({:update_subscription, subscription_id, new_entity_ids}, _from, state) do
        BaseIndex.handle_update_subscription(
          @table_name,
          @entity_type,
          @entity_type_string,
          subscription_id,
          new_entity_ids,
          state
        )
      end

      @impl true
      def handle_call({:remove_subscription, subscription_id}, _from, state) do
        BaseIndex.handle_remove_subscription(
          @table_name,
          @entity_type,
          @entity_type_string,
          subscription_id,
          state
        )
      end

      @impl true
      def handle_call(:get_stats, _from, state) do
        stats =
          BaseIndex.calculate_stats(
            @table_name,
            @entity_type_string,
            state
          )

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
        BaseIndex.cleanup_empty_entries(@table_name)
        Process.send_after(self(), :cleanup, @cleanup_interval)
        {:noreply, state}
      end
    end
  end

  # ============================================================================
  # Shared Implementation Functions
  # ============================================================================

  @doc """
  Shared implementation for single entity lookup.
  """
  def find_subscriptions_for_entity(table_name, entity_id, entity_type) do
    start_time = System.monotonic_time()

    result =
      case :ets.lookup(table_name, entity_id) do
        [{^entity_id, subscription_ids}] ->
          subs = MapSet.to_list(subscription_ids)

          if length(subs) > 0 do
            require Logger

            Logger.info(
              "[INFO] #{entity_type}Index lookup found subscriptions - " <>
                "entity_id: #{entity_id}, subscriptions: #{inspect(subs)}"
            )
          end

          subs

        [] ->
          []
      end

    duration = System.monotonic_time() - start_time

    emit_index_telemetry(entity_type, :lookup, duration, %{
      entity_id: entity_id,
      result_count: length(result)
    })

    result
  end

  @doc """
  Shared implementation for batch entity lookup.
  """
  def find_subscriptions_for_entities(table_name, entity_ids, entity_type) do
    start_time = System.monotonic_time()

    result =
      entity_ids
      |> Enum.reduce(MapSet.new(), fn entity_id, acc ->
        case :ets.lookup(table_name, entity_id) do
          [{^entity_id, subscription_ids}] -> MapSet.union(acc, subscription_ids)
          [] -> acc
        end
      end)
      |> MapSet.to_list()

    duration = System.monotonic_time() - start_time

    emit_index_telemetry(entity_type, :batch_lookup, duration, %{
      entity_count: length(entity_ids),
      result_count: length(result)
    })

    result
  end

  @doc """
  Shared implementation for adding subscriptions.
  """
  def handle_add_subscription(
        table_name,
        entity_type,
        entity_type_string,
        subscription_id,
        entity_ids,
        state
      ) do
    start_time = System.monotonic_time()
    entity_count = length(entity_ids)

    # Log for large entity lists
    if entity_count > 20 do
      require Logger

      Logger.info("[INFO] Adding subscription with large #{entity_type_string} list",
        subscription_id: subscription_id,
        entity_count: entity_count
      )
    end

    # Update the forward index (entity_id -> subscription_ids)
    # Use sequential processing to avoid race conditions with ETS operations
    Enum.each(entity_ids, fn entity_id ->
      update_entity_index(table_name, entity_id, subscription_id, :add)
    end)

    # Update the reverse index
    new_reverse_index = Map.put(state.reverse_index, subscription_id, entity_ids)

    duration = System.monotonic_time() - start_time

    emit_index_telemetry(entity_type, :add, duration, %{
      subscription_id: subscription_id,
      entity_count: entity_count
    })

    {:reply, :ok, %{state | reverse_index: new_reverse_index}}
  end

  @doc """
  Shared implementation for updating subscriptions.
  """
  def handle_update_subscription(
        table_name,
        entity_type,
        _entity_type_string,
        subscription_id,
        new_entity_ids,
        state
      ) do
    start_time = System.monotonic_time()

    # Get the old entity IDs
    old_entity_ids = Map.get(state.reverse_index, subscription_id, [])

    # Find entities to remove and add
    to_remove = MapSet.difference(MapSet.new(old_entity_ids), MapSet.new(new_entity_ids))
    to_add = MapSet.difference(MapSet.new(new_entity_ids), MapSet.new(old_entity_ids))

    # Remove subscription from old entities
    to_remove_list = MapSet.to_list(to_remove)
    to_add_list = MapSet.to_list(to_add)

    # Process removals with parallel processing for large lists
    if length(to_remove_list) > 100 do
      Task.Supervisor.async_stream(
        WandererKills.TaskSupervisor,
        to_remove_list,
        fn entity_id ->
          update_entity_index(table_name, entity_id, subscription_id, :remove)
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 30_000
      )
      |> Stream.run()
    else
      Enum.each(to_remove_list, fn entity_id ->
        update_entity_index(table_name, entity_id, subscription_id, :remove)
      end)
    end

    # Process additions with parallel processing for large lists
    if length(to_add_list) > 100 do
      Task.Supervisor.async_stream(
        WandererKills.TaskSupervisor,
        to_add_list,
        fn entity_id ->
          update_entity_index(table_name, entity_id, subscription_id, :add)
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 30_000
      )
      |> Stream.run()
    else
      Enum.each(to_add_list, fn entity_id ->
        update_entity_index(table_name, entity_id, subscription_id, :add)
      end)
    end

    # Update the reverse index
    new_reverse_index =
      if new_entity_ids == [] do
        Map.delete(state.reverse_index, subscription_id)
      else
        Map.put(state.reverse_index, subscription_id, new_entity_ids)
      end

    duration = System.monotonic_time() - start_time

    emit_index_telemetry(entity_type, :update, duration, %{
      subscription_id: subscription_id,
      old_count: length(old_entity_ids),
      new_count: length(new_entity_ids)
    })

    {:reply, :ok, %{state | reverse_index: new_reverse_index}}
  end

  @doc """
  Shared implementation for removing subscriptions.
  """
  def handle_remove_subscription(
        table_name,
        entity_type,
        _entity_type_string,
        subscription_id,
        state
      ) do
    start_time = System.monotonic_time()

    # Get all entity IDs for this subscription
    entity_ids = Map.get(state.reverse_index, subscription_id, [])

    # Remove the subscription from all entity entries
    # Use sequential processing to avoid race conditions with ETS operations
    Enum.each(entity_ids, fn entity_id ->
      update_entity_index(table_name, entity_id, subscription_id, :remove)
    end)

    # Remove from reverse index
    new_reverse_index = Map.delete(state.reverse_index, subscription_id)

    duration = System.monotonic_time() - start_time

    emit_index_telemetry(entity_type, :remove, duration, %{
      subscription_id: subscription_id,
      entity_count: length(entity_ids)
    })

    {:reply, :ok, %{state | reverse_index: new_reverse_index}}
  end

  @doc """
  Shared implementation for calculating statistics.
  """
  def calculate_stats(table_name, entity_type_string, state) do
    total_subscriptions = map_size(state.reverse_index)
    total_entity_entries = :ets.info(table_name, :size)
    memory_usage_bytes = :ets.info(table_name, :memory) * :erlang.system_info(:wordsize)

    # Calculate total entity subscriptions (sum of all entity lists)
    total_entity_subscriptions =
      Enum.reduce(state.reverse_index, 0, fn {_, entities}, acc ->
        acc + length(entities)
      end)

    base_stats = %{
      total_subscriptions: total_subscriptions,
      memory_usage_bytes: memory_usage_bytes
    }

    # Add entity-specific stats based on the entity type
    case entity_type_string do
      "character" ->
        Map.merge(base_stats, %{
          total_character_entries: total_entity_entries,
          total_character_subscriptions: total_entity_subscriptions
        })

      "system" ->
        Map.merge(base_stats, %{
          total_system_entries: total_entity_entries,
          total_system_subscriptions: total_entity_subscriptions
        })

      _ ->
        # For other entity types, use generic keys
        Map.merge(base_stats, %{
          total_entity_entries: total_entity_entries,
          total_entity_subscriptions: total_entity_subscriptions
        })
    end
  end

  @doc """
  Performs periodic cleanup of empty entries.

  This is a safety measure to remove any ETS entries that might have
  empty subscription sets due to race conditions.
  """
  def cleanup_empty_entries(table_name) do
    :ets.foldl(
      fn {entity_id, subscription_ids}, acc ->
        if MapSet.size(subscription_ids) == 0 do
          :ets.delete(table_name, entity_id)
        end

        acc
      end,
      :ok,
      table_name
    )
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Emits appropriate telemetry based on entity type
  defp emit_index_telemetry(:character, operation, duration, metadata) do
    Telemetry.character_index(operation, duration, metadata)
  end

  defp emit_index_telemetry(:system, operation, duration, metadata) do
    Telemetry.system_index(operation, duration, metadata)
  end

  # For test entities or other entity types, emit generic telemetry
  defp emit_index_telemetry(entity_type, operation, duration, metadata)
       when is_atom(entity_type) do
    :telemetry.execute(
      [:wanderer_kills, entity_type, :index],
      %{duration: duration},
      Map.put(metadata, :operation, operation)
    )
  end

  # Updates the forward index (entity_id -> subscription_ids)
  defp update_entity_index(table_name, entity_id, subscription_id, action) do
    case :ets.lookup(table_name, entity_id) do
      [{^entity_id, existing_subscriptions}] ->
        new_subscriptions =
          case action do
            :add -> MapSet.put(existing_subscriptions, subscription_id)
            :remove -> MapSet.delete(existing_subscriptions, subscription_id)
          end

        if MapSet.size(new_subscriptions) == 0 do
          :ets.delete(table_name, entity_id)
        else
          :ets.insert(table_name, {entity_id, new_subscriptions})
        end

      [] when action == :add ->
        :ets.insert(table_name, {entity_id, MapSet.new([subscription_id])})

      [] when action == :remove ->
        # Entity not found, nothing to remove
        :ok
    end
  end
end
