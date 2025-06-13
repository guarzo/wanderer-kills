defmodule WandererKills.Observability.SubscriptionHealthSimpleTest do
  use ExUnit.Case, async: false

  # Create test implementation using the unified health check
  defmodule TestCharacterHealth do
    use WandererKills.Observability.SubscriptionHealth,
      index_module: WandererKills.Subscriptions.CharacterIndexNew,
      entity_type: :character
  end

  alias WandererKills.Subscriptions.CharacterIndexNew

  test "health check module generation works" do
    # Start the index
    {:ok, pid} = CharacterIndexNew.start_link([])
    
    # Test health check
    health = TestCharacterHealth.check_health()
    
    assert health.healthy == true
    assert health.status == "healthy"
    assert health.details.component == "character_subscriptions"
    
    # Test metrics
    metrics = TestCharacterHealth.get_metrics()
    
    assert metrics.component == "character_subscriptions"
    assert is_map(metrics.metrics)
    
    # Test default config
    config = TestCharacterHealth.default_config()
    assert config[:timeout_ms] == 5_000
    
    # Stop the GenServer
    GenServer.stop(pid)
  end

  test "health check includes all expected checks" do
    {:ok, pid} = CharacterIndexNew.start_link([])
    
    health = TestCharacterHealth.check_health()
    
    checks = health.details.checks
    assert Map.has_key?(checks, :index_availability)
    assert Map.has_key?(checks, :index_performance)
    assert Map.has_key?(checks, :memory_usage)
    assert Map.has_key?(checks, :subscription_counts)
    
    # All should be healthy for empty index
    assert checks.index_availability.status == :healthy
    assert checks.index_performance.status == :healthy
    assert checks.memory_usage.status == :healthy
    assert checks.subscription_counts.status == :healthy
    
    GenServer.stop(pid)
  end

  test "metrics calculation works correctly" do
    {:ok, pid} = CharacterIndexNew.start_link([])
    
    # Add some test data
    CharacterIndexNew.add_subscription("sub_1", [123, 456])
    CharacterIndexNew.add_subscription("sub_2", [456, 789])
    
    metrics = TestCharacterHealth.get_metrics()
    m = metrics.metrics
    
    assert m.total_subscriptions == 2
    assert m.total_entity_entries == 3  # 123, 456, 789
    assert m.total_entity_subscriptions == 4  # 2 + 2
    assert is_number(m.memory_usage_bytes)
    assert m.memory_usage_mb >= 0.0
    assert m.avg_entities_per_subscription == 2.0  # 4 / 2
    
    GenServer.stop(pid)
  end
end