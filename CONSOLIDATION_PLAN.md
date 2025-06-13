# Subscription Index Consolidation Plan

## Overview

This document outlines the detailed implementation plan for consolidating the duplicate code between CharacterIndex and SystemIndex implementations, along with standardizing health checks and telemetry patterns.

**Goals:**
- Eliminate ~600 lines of duplicated code (80% duplication)
- Standardize implementation patterns across entity types
- Maintain type safety and performance characteristics
- Improve maintainability and reduce future duplication risk

## Current State Analysis

### Code Duplication Metrics
- **CharacterIndex**: ~400 lines
- **SystemIndex**: ~350 lines
- **Estimated Duplication**: ~80% (300+ lines)
- **Health Check Duplication**: ~70% (150+ lines)
- **Test Duplication**: ~90% (200+ lines)

### Critical Inconsistencies
1. **ETS Configuration**: SystemIndex missing `write_concurrency: true`
2. **Statistics**: Different metrics between implementations
3. **Health Checks**: Different architectural approaches
4. **Update Logic**: CharacterIndex uses separate functions, SystemIndex uses case statements
5. **Cleanup Patterns**: Different scheduling and implementation approaches

## Implementation Plan

### Phase 1: Create Shared Index Foundation

#### 1.1 Create BaseIndex Behaviour
**File**: `/lib/wanderer_kills/subscriptions/index_behaviour.ex`

```elixir
defmodule WandererKills.Subscriptions.IndexBehaviour do
  @moduledoc """
  Behaviour definition for subscription index implementations.
  
  Defines the common interface that all subscription indexes must implement,
  whether for characters, systems, or future entity types.
  """
  
  @type entity_id :: integer()
  @type subscription_id :: String.t()
  @type index_stats :: %{
    total_subscriptions: non_neg_integer(),
    total_entity_entries: non_neg_integer(),
    total_entity_subscriptions: non_neg_integer(),
    memory_usage_bytes: non_neg_integer()
  }
  
  @callback start_link(keyword()) :: GenServer.on_start()
  @callback add_subscription(subscription_id(), [entity_id()]) :: :ok
  @callback update_subscription(subscription_id(), [entity_id()]) :: :ok  
  @callback remove_subscription(subscription_id()) :: :ok
  @callback find_subscriptions_for_entity(entity_id()) :: [subscription_id()]
  @callback find_subscriptions_for_entities([entity_id()]) :: [subscription_id()]
  @callback get_stats() :: index_stats()
  @callback clear() :: :ok
end
```

#### 1.2 Create BaseIndex Implementation
**File**: `/lib/wanderer_kills/subscriptions/base_index.ex`

```elixir
defmodule WandererKills.Subscriptions.BaseIndex do
  @moduledoc """
  Shared GenServer implementation for ETS-based subscription indexes.
  
  This module provides a common implementation that can be used by both
  CharacterIndex and SystemIndex to eliminate code duplication while
  maintaining type safety and performance characteristics.
  """
  
  defmacro __using__(opts) do
    entity_type = Keyword.fetch!(opts, :entity_type)
    entity_type_string = Atom.to_string(entity_type)
    table_name = Keyword.fetch!(opts, :table_name)
    
    quote do
      use GenServer
      require Logger
      alias WandererKills.Observability.Telemetry
      
      @behaviour WandererKills.Subscriptions.IndexBehaviour
      
      @entity_type unquote(entity_type)
      @entity_type_string unquote(entity_type_string)
      @table_name unquote(table_name)
      @cleanup_interval :timer.minutes(5)
      
      # Client API functions
      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end
      
      def add_subscription(subscription_id, entity_ids) when is_list(entity_ids) do
        GenServer.call(__MODULE__, {:add_subscription, subscription_id, entity_ids})
      end
      
      def update_subscription(subscription_id, entity_ids) when is_list(entity_ids) do
        GenServer.call(__MODULE__, {:update_subscription, subscription_id, entity_ids})
      end
      
      def remove_subscription(subscription_id) do
        GenServer.call(__MODULE__, {:remove_subscription, subscription_id})
      end
      
      def find_subscriptions_for_entity(entity_id) when is_integer(entity_id) do
        WandererKills.Subscriptions.BaseIndex.find_subscriptions_for_entity(
          @table_name, entity_id, @entity_type
        )
      end
      
      def find_subscriptions_for_entities(entity_ids) when is_list(entity_ids) do
        WandererKills.Subscriptions.BaseIndex.find_subscriptions_for_entities(
          @table_name, entity_ids, @entity_type
        )
      end
      
      def get_stats do
        GenServer.call(__MODULE__, :get_stats)
      end
      
      def clear do
        GenServer.call(__MODULE__, :clear)
      end
      
      # Server Callbacks
      @impl true
      def init(_opts) do
        Logger.info("#{__MODULE__} starting...")
        
        # Standardized ETS configuration
        :ets.new(@table_name, [
          :set, :public, :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])
        
        # Schedule periodic cleanup
        Process.send_after(self(), :cleanup, @cleanup_interval)
        
        # Initialize reverse index
        reverse_index = %{}
        
        Logger.info("#{__MODULE__} started successfully")
        {:ok, %{reverse_index: reverse_index}}
      end
      
      @impl true
      def handle_call({:add_subscription, subscription_id, entity_ids}, _from, state) do
        WandererKills.Subscriptions.BaseIndex.handle_add_subscription(
          @table_name, @entity_type, subscription_id, entity_ids, state
        )
      end
      
      @impl true
      def handle_call({:update_subscription, subscription_id, new_entity_ids}, _from, state) do
        WandererKills.Subscriptions.BaseIndex.handle_update_subscription(
          @table_name, @entity_type, subscription_id, new_entity_ids, state
        )
      end
      
      @impl true
      def handle_call({:remove_subscription, subscription_id}, _from, state) do
        WandererKills.Subscriptions.BaseIndex.handle_remove_subscription(
          @table_name, @entity_type, subscription_id, state
        )
      end
      
      @impl true
      def handle_call(:get_stats, _from, state) do
        stats = WandererKills.Subscriptions.BaseIndex.calculate_stats(
          @table_name, @entity_type_string, state
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
        WandererKills.Subscriptions.BaseIndex.cleanup_empty_entries(@table_name)
        Process.send_after(self(), :cleanup, @cleanup_interval)
        {:noreply, state}
      end
    end
  end
  
  # Shared implementation functions
  def find_subscriptions_for_entity(table_name, entity_id, entity_type) do
    start_time = System.monotonic_time()
    
    result = case :ets.lookup(table_name, entity_id) do
      [{^entity_id, subscription_ids}] -> MapSet.to_list(subscription_ids)
      [] -> []
    end
    
    duration = System.monotonic_time() - start_time
    emit_index_telemetry(entity_type, :lookup, duration, %{
      entity_id: entity_id,
      result_count: length(result)
    })
    
    result
  end
  
  def find_subscriptions_for_entities(table_name, entity_ids, entity_type) do
    start_time = System.monotonic_time()
    
    result = entity_ids
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
  
  def handle_add_subscription(table_name, entity_type, subscription_id, entity_ids, state) do
    start_time = System.monotonic_time()
    entity_count = length(entity_ids)
    
    # Log for large entity lists
    if entity_count > 20 do
      Logger.info("📊 Adding subscription with large #{entity_type} list",
        subscription_id: subscription_id,
        entity_count: entity_count,
        entity_type: entity_type
      )
    end
    
    # Update the forward index
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
  
  # Additional shared functions...
  
  defp emit_index_telemetry(:character, operation, duration, metadata) do
    Telemetry.character_index(operation, duration, metadata)
  end
  
  defp emit_index_telemetry(:system, operation, duration, metadata) do
    Telemetry.system_index(operation, duration, metadata)
  end
  
  defp update_entity_index(table_name, entity_id, subscription_id, action) do
    case :ets.lookup(table_name, entity_id) do
      [{^entity_id, existing_subscriptions}] ->
        new_subscriptions = case action do
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
        :ok
    end
  end
  
  def cleanup_empty_entries(table_name) do
    :ets.foldl(fn {entity_id, subscription_ids}, acc ->
      if MapSet.size(subscription_ids) == 0 do
        :ets.delete(table_name, entity_id)
      end
      acc
    end, :ok, table_name)
  end
  
  def calculate_stats(table_name, entity_type_string, state) do
    total_subscriptions = map_size(state.reverse_index)
    total_entity_entries = :ets.info(table_name, :size)
    memory_usage_bytes = :ets.info(table_name, :memory) * :erlang.system_info(:wordsize)
    
    # Calculate total entity subscriptions
    total_entity_subscriptions = Enum.reduce(state.reverse_index, 0, fn {_, entities}, acc ->
      acc + length(entities)
    end)
    
    %{
      total_subscriptions: total_subscriptions,
      "total_#{entity_type_string}_entries": total_entity_entries,
      "total_#{entity_type_string}_subscriptions": total_entity_subscriptions,
      memory_usage_bytes: memory_usage_bytes
    }
  end
end
```

#### 1.3 Update CharacterIndex to use BaseIndex
**File**: `/lib/wanderer_kills/subscriptions/character_index.ex`

```elixir
defmodule WandererKills.Subscriptions.CharacterIndex do
  @moduledoc """
  Maintains an ETS-based index for fast character -> subscription lookups.
  
  This module uses the BaseIndex shared implementation to provide O(1) lookups
  for character-based subscription matching.
  """
  
  use WandererKills.Subscriptions.BaseIndex,
    entity_type: :character,
    table_name: :character_subscription_index
end
```

#### 1.4 Update SystemIndex to use BaseIndex
**File**: `/lib/wanderer_kills/subscriptions/system_index.ex`

```elixir
defmodule WandererKills.Subscriptions.SystemIndex do
  @moduledoc """
  Maintains an ETS-based index for fast system -> subscription lookups.
  
  This module uses the BaseIndex shared implementation to provide O(1) lookups
  for system-based subscription matching.
  """
  
  use WandererKills.Subscriptions.BaseIndex,
    entity_type: :system,
    table_name: :system_subscription_index
end
```

### Phase 2: Consolidate Health Checks

#### 2.1 Create Unified Health Check Module
**File**: `/lib/wanderer_kills/observability/subscription_health.ex`

```elixir
defmodule WandererKills.Observability.SubscriptionHealth do
  @moduledoc """
  Unified health check implementation for subscription indexes.
  
  Provides standardized health checking for both character and system
  subscription indexes using a common implementation pattern.
  """
  
  @behaviour WandererKills.Observability.HealthCheckBehaviour
  
  alias WandererKills.Support.Clock
  
  defmacro __using__(opts) do
    index_module = Keyword.fetch!(opts, :index_module)
    entity_type = Keyword.fetch!(opts, :entity_type)
    component_name = "#{entity_type}_subscriptions"
    
    quote do
      @behaviour WandererKills.Observability.HealthCheckBehaviour
      
      @index_module unquote(index_module)
      @entity_type unquote(entity_type)
      @component_name unquote(component_name)
      
      @impl true
      def check_health(_opts \\ []) do
        WandererKills.Observability.SubscriptionHealth.check_health(
          @index_module, @entity_type, @component_name
        )
      end
      
      @impl true
      def get_metrics(_opts \\ []) do
        WandererKills.Observability.SubscriptionHealth.get_metrics(
          @index_module, @entity_type, @component_name
        )
      end
      
      @impl true
      def default_config do
        [timeout_ms: 5_000]
      end
    end
  end
  
  def check_health(index_module, entity_type, component_name) do
    timestamp = DateTime.utc_now()
    
    checks = %{
      index_availability: check_index_availability(index_module),
      index_performance: check_index_performance(index_module, entity_type),
      memory_usage: check_memory_usage(index_module),
      subscription_counts: check_subscription_counts(index_module)
    }
    
    metrics = collect_metrics(index_module, entity_type)
    overall_status = determine_overall_status(checks)
    
    %{
      healthy: overall_status == :healthy,
      status: Atom.to_string(overall_status),
      details: %{
        component: component_name,
        checks: checks,
        metrics: metrics
      },
      timestamp: Clock.now_iso8601()
    }
  end
  
  def get_metrics(index_module, entity_type, component_name) do
    %{
      component: component_name,
      timestamp: Clock.now_iso8601(),
      metrics: collect_metrics(index_module, entity_type)
    }
  end
  
  # Shared health check implementations...
  defp check_index_availability(index_module) do
    try do
      stats = index_module.get_stats()
      if is_map(stats) and Map.has_key?(stats, :total_subscriptions) do
        %{status: :healthy, message: "#{index_module} responding normally"}
      else
        %{status: :unhealthy, message: "#{index_module} returning invalid stats"}
      end
    rescue
      error ->
        %{status: :unhealthy, message: "#{index_module} not available: #{inspect(error)}"}
    end
  end
  
  # Additional shared functions...
end
```

#### 2.2 Update CharacterSubscriptionHealth
**File**: `/lib/wanderer_kills/observability/character_subscription_health.ex`

```elixir
defmodule WandererKills.Observability.CharacterSubscriptionHealth do
  @moduledoc """
  Health check implementation for character subscription components.
  """
  
  use WandererKills.Observability.SubscriptionHealth,
    index_module: WandererKills.Subscriptions.CharacterIndex,
    entity_type: :character
end
```

#### 2.3 Update SystemSubscriptionHealth
**File**: `/lib/wanderer_kills/observability/system_subscription_health.ex`

```elixir
defmodule WandererKills.Observability.SystemSubscriptionHealth do
  @moduledoc """
  Health check implementation for system subscription components.
  """
  
  use WandererKills.Observability.SubscriptionHealth,
    index_module: WandererKills.Subscriptions.SystemIndex,
    entity_type: :system
end
```

### Phase 3: Standardize Test Patterns

#### 3.1 Create Shared Test Module
**File**: `/test/support/index_test_helpers.ex`

```elixir
defmodule WandererKills.Test.IndexTestHelpers do
  @moduledoc """
  Shared test patterns for subscription index testing.
  
  Provides parameterized test helpers that work for both character
  and system subscription index testing.
  """
  
  def test_basic_subscription(index_module, entity_id) do
    index_module.add_subscription("sub_1", [entity_id])
    
    assert index_module.find_subscriptions_for_entity(entity_id) == ["sub_1"]
    assert index_module.find_subscriptions_for_entity(entity_id + 1) == []
  end
  
  def test_multiple_entities(index_module, entity_ids) do
    index_module.add_subscription("sub_1", entity_ids)
    
    Enum.each(entity_ids, fn entity_id ->
      assert index_module.find_subscriptions_for_entity(entity_id) == ["sub_1"]
    end)
  end
  
  def test_performance_with_scale(index_module, entity_id_generator, scale \\ 1000) do
    # Generate subscriptions
    for i <- 1..scale do
      entities = entity_id_generator.(i)
      index_module.add_subscription("sub_#{i}", entities)
    end
    
    # Test lookup performance
    test_entity = entity_id_generator.(scale / 2) |> List.first()
    
    {time, result} = :timer.tc(fn ->
      index_module.find_subscriptions_for_entity(test_entity)
    end)
    
    assert length(result) > 0
    assert time < 1_000  # Under 1ms
  end
  
  # Additional shared test patterns...
end
```

#### 3.2 Update CharacterIndexTest
**File**: `/test/wanderer_kills/subscriptions/character_index_test.exs`

```elixir
defmodule WandererKills.Subscriptions.CharacterIndexTest do
  use ExUnit.Case, async: false
  
  alias WandererKills.Subscriptions.CharacterIndex
  alias WandererKills.Test.IndexTestHelpers
  
  setup do
    CharacterIndex.clear()
    on_exit(fn -> CharacterIndex.clear() end)
    :ok
  end
  
  describe "basic functionality" do
    test "adds subscription with single character" do
      IndexTestHelpers.test_basic_subscription(CharacterIndex, 123)
    end
    
    test "adds subscription with multiple characters" do
      IndexTestHelpers.test_multiple_entities(CharacterIndex, [123, 456, 789])
    end
  end
  
  describe "performance" do
    test "handles large number of subscriptions efficiently" do
      character_generator = fn i -> Enum.to_list((i * 10)..(i * 10 + 9)) end
      IndexTestHelpers.test_performance_with_scale(CharacterIndex, character_generator)
    end
  end
  
  # Character-specific tests that can't be generalized...
end
```

### Phase 4: Implementation Timeline

#### Week 1: Foundation
- [ ] Create `IndexBehaviour` module
- [ ] Implement `BaseIndex` module with core functionality
- [ ] Create unit tests for `BaseIndex`

#### Week 2: Index Migration
- [ ] Update `CharacterIndex` to use `BaseIndex`
- [ ] Update `SystemIndex` to use `BaseIndex`
- [ ] Run full test suite to ensure no regressions
- [ ] Update integration points in `SubscriptionManager`

#### Week 3: Health Check Consolidation
- [ ] Create unified `SubscriptionHealth` module
- [ ] Update `CharacterSubscriptionHealth` and `SystemSubscriptionHealth`
- [ ] Create shared test helpers
- [ ] Update health check integration in `ApplicationHealth`

#### Week 4: Testing and Documentation
- [ ] Update all test files to use shared patterns
- [ ] Performance testing and optimization
- [ ] Update documentation and module docs
- [ ] Code review and cleanup

### Phase 5: Migration Strategy

#### 5.1 Backwards Compatibility
- Maintain existing public APIs during transition
- Use feature flags for gradual rollout
- Extensive test coverage during migration

#### 5.2 Risk Mitigation
- Implement changes behind configuration flags
- Gradual migration of functionality
- Comprehensive integration testing
- Performance benchmarking before/after

#### 5.3 Rollback Plan
- Maintain original implementations as backup
- Database/ETS state migration procedures
- Monitoring and alerting for performance regressions

## Expected Outcomes

### Code Reduction
- **~600 lines** of duplicated code eliminated
- **~80% reduction** in index implementation maintenance
- **Unified test patterns** reducing test duplication by ~70%

### Consistency Improvements
- **Standardized ETS configuration** across all indexes
- **Unified statistics and metrics** collection
- **Consistent health check patterns**
- **Standardized telemetry integration**

### Maintainability Benefits
- **Single source of truth** for index implementation patterns
- **Easier addition** of new entity types (ships, alliances, etc.)
- **Reduced cognitive load** for developers
- **Consistent error handling** and logging patterns

### Performance Characteristics
- **No performance regression** expected
- **Potential memory savings** from eliminated duplicate code
- **Consistent optimization** patterns across all indexes
- **Improved observability** and monitoring

## Future Considerations

### Additional Entity Types
The consolidated approach will make it trivial to add new subscription entity types:
- **Ship Types**: Track specific ship types in killmails
- **Alliances**: Track alliance-based killmails
- **Corporations**: Track corporation-based killmails
- **Regions**: Track region-based killmails

### Enhanced Features
- **Composite Indexes**: Support for multi-entity lookups
- **Temporal Filtering**: Time-based subscription filtering
- **Performance Optimizations**: Batch processing improvements
- **Advanced Analytics**: Enhanced metrics and reporting

### Monitoring and Observability
- **Unified telemetry patterns** for all entity types
- **Standardized performance metrics** across indexes
- **Common alerting thresholds** and health checks
- **Centralized configuration** management

This consolidation plan provides a clear path to eliminate significant code duplication while improving maintainability, consistency, and extensibility of the subscription system.