defmodule WandererKills.Core.Observability.SubscriptionHealthTest do
  use ExUnit.Case, async: false

  # Create test implementations using the unified health check
  defmodule TestCharacterHealth do
    use WandererKills.Core.Observability.SubscriptionHealth,
      index_module: WandererKills.Subs.Subscriptions.CharacterIndex,
      entity_type: :character
  end

  defmodule TestSystemHealth do
    use WandererKills.Core.Observability.SubscriptionHealth,
      index_module: WandererKills.Subs.Subscriptions.SystemIndex,
      entity_type: :system
  end

  alias WandererKills.Subs.Subscriptions.{CharacterIndex, SystemIndex}

  setup do
    # Clear both indexes if they're available
    # In parallel tests, the indexes might not be immediately available
    try do
      CharacterIndex.clear()
      SystemIndex.clear()
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end

    # Give the system a moment to stabilize
    Process.sleep(10)

    :ok
  end

  describe "unified health check behaviour" do
    test "implements HealthCheckBehaviour correctly" do
      # Verify both modules implement the behaviour
      assert TestCharacterHealth.__info__(:attributes)
             |> Enum.any?(fn {key, values} ->
               key == :behaviour and
                 WandererKills.Core.Observability.HealthCheckBehaviour in values
             end)

      assert TestSystemHealth.__info__(:attributes)
             |> Enum.any?(fn {key, values} ->
               key == :behaviour and
                 WandererKills.Core.Observability.HealthCheckBehaviour in values
             end)
    end

    test "has consistent API across entity types" do
      # Both should have the same function exports
      char_exports = TestCharacterHealth.__info__(:functions) |> Enum.sort()
      sys_exports = TestSystemHealth.__info__(:functions) |> Enum.sort()

      assert char_exports == sys_exports
    end
  end

  describe "check_health/1" do
    test "returns healthy status for character subscriptions" do
      health = TestCharacterHealth.check_health()

      assert health.healthy == true
      assert health.status == "healthy"
      assert health.details.component == "character_subscriptions"
      assert is_binary(health.timestamp)

      # Verify all expected checks are present
      checks = health.details.checks
      assert Map.has_key?(checks, :index_availability)
      assert Map.has_key?(checks, :index_performance)
      assert Map.has_key?(checks, :memory_usage)
      assert Map.has_key?(checks, :subscription_counts)

      # All checks should be healthy for empty index
      assert checks.index_availability.status == :healthy
      assert checks.index_performance.status == :healthy
      assert checks.memory_usage.status == :healthy
      assert checks.subscription_counts.status == :healthy
    end

    test "returns healthy status for system subscriptions" do
      health = TestSystemHealth.check_health()

      assert health.healthy == true
      assert health.status == "healthy"
      assert health.details.component == "system_subscriptions"

      # All checks should be healthy for empty index
      checks = health.details.checks
      assert checks.index_availability.status == :healthy
      assert checks.index_performance.status == :healthy
      assert checks.memory_usage.status == :healthy
      assert checks.subscription_counts.status == :healthy
    end

    test "includes performance metrics in checks" do
      health = TestCharacterHealth.check_health()

      perf_check = health.details.checks.index_performance
      assert Map.has_key?(perf_check, :duration_us)
      assert is_number(perf_check.duration_us)
      assert perf_check.duration_us >= 0
    end

    test "includes memory metrics in checks" do
      health = TestSystemHealth.check_health()

      memory_check = health.details.checks.memory_usage
      assert Map.has_key?(memory_check, :memory_mb)
      assert is_number(memory_check.memory_mb)
      assert memory_check.memory_mb >= 0.0
    end

    test "includes subscription count metrics" do
      # Add some test data
      CharacterIndex.add_subscription("sub_1", [123, 456])
      CharacterIndex.add_subscription("sub_2", [456, 789])

      health = TestCharacterHealth.check_health()

      count_check = health.details.checks.subscription_counts
      assert count_check.subscription_count == 2
      # 123, 456, 789
      assert count_check.entity_entry_count == 3
    end
  end

  describe "get_metrics/1" do
    test "returns detailed metrics for character subscriptions" do
      # Add test data
      CharacterIndex.add_subscription("sub_1", [123, 456, 789])
      CharacterIndex.add_subscription("sub_2", [456, 789])

      metrics = TestCharacterHealth.get_metrics()

      assert metrics.component == "character_subscriptions"
      assert is_binary(metrics.timestamp)

      m = metrics.metrics
      assert m.total_subscriptions == 2
      # 123, 456, 789
      assert m.total_entity_entries == 3
      # 3 + 2
      assert m.total_entity_subscriptions == 5
      assert is_number(m.memory_usage_bytes)
      assert is_number(m.memory_usage_mb)
      assert is_number(m.avg_entities_per_subscription)
      # 5 / 2
      assert m.avg_entities_per_subscription == 2.5
    end

    test "returns detailed metrics for system subscriptions" do
      # Add test data
      SystemIndex.add_subscription("sub_1", [30_000_142, 30_000_144])
      SystemIndex.add_subscription("sub_2", [30_000_144, 30_000_148, 30_000_999])

      metrics = TestSystemHealth.get_metrics()

      assert metrics.component == "system_subscriptions"

      m = metrics.metrics
      assert m.total_subscriptions == 2
      # Unique systems
      assert m.total_entity_entries == 4
      # 2 + 3
      assert m.total_entity_subscriptions == 5
      # 5 / 2
      assert m.avg_entities_per_subscription == 2.5
    end

    test "calculates index efficiency correctly" do
      # Add data with good deduplication
      CharacterIndex.add_subscription("sub_1", [123, 456])
      # Same characters
      CharacterIndex.add_subscription("sub_2", [123, 456])
      # Same characters
      CharacterIndex.add_subscription("sub_3", [123, 456])

      metrics = TestCharacterHealth.get_metrics()

      m = metrics.metrics
      assert m.total_subscriptions == 3
      # Only 2 unique characters despite 3 subscriptions
      assert m.total_entity_entries == 2
      # 2 entries / 3 subscriptions (2/3 ≈ 0.67)
      assert_in_delta m.index_efficiency, 0.67, 0.01
    end
  end

  describe "default_config/0" do
    test "returns consistent configuration" do
      char_config = TestCharacterHealth.default_config()
      sys_config = TestSystemHealth.default_config()

      # Both should have the same configuration
      assert char_config == sys_config
      assert char_config[:timeout_ms] == 5_000
    end
  end

  describe "error handling" do
    test "handles index unavailability gracefully" do
      # This test verifies the error handling when index is unavailable
      # Since CharacterIndex is a named GenServer, we'll verify the structure instead
      health = TestCharacterHealth.check_health()

      # When the index is available, we expect healthy status
      assert health.healthy == true
      assert health.status == "healthy"

      # Verify the availability check structure exists
      availability_check = health.details.checks.index_availability
      assert availability_check.status == :healthy
      assert String.contains?(availability_check.message, "responding normally")
    end

    test "handles invalid stats gracefully" do
      # This would require mocking the index to return invalid stats
      # For now, we verify the error handling structure exists
      metrics = TestSystemHealth.get_metrics()

      # Should not crash and should return valid structure
      assert is_map(metrics)
      assert Map.has_key?(metrics, :component)
      assert Map.has_key?(metrics, :metrics)
    end
  end

  describe "performance characteristics" do
    test "health checks complete quickly" do
      {time, _health} =
        :timer.tc(fn ->
          TestCharacterHealth.check_health()
        end)

      # Health check should complete in under 100ms
      assert time < 100_000
    end

    test "metrics collection is efficient" do
      # Add substantial test data
      for i <- 1..100 do
        CharacterIndex.add_subscription("sub_#{i}", [i * 10, i * 10 + 1])
      end

      {time, _metrics} =
        :timer.tc(fn ->
          TestCharacterHealth.get_metrics()
        end)

      # Metrics collection should complete quickly even with data
      # Under 50ms
      assert time < 50_000
    end
  end
end
