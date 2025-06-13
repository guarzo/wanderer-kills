defmodule WandererKills.Observability.SubscriptionHealth do
  @moduledoc """
  Unified health check implementation for subscription indexes.

  Provides standardized health checking for both character and system
  subscription indexes using a common implementation pattern. This eliminates
  code duplication and ensures consistent health monitoring across all
  entity types.

  ## Usage

      defmodule MyEntitySubscriptionHealth do
        use WandererKills.Observability.SubscriptionHealth,
          index_module: MyEntityIndex,
          entity_type: :my_entity
      end

  ## Health Checks

  **Index Availability:**
  - Verifies index GenServer is responding
  - Validates stats return expected format
  - Reports index module status

  **Performance Monitoring:**
  - Tests single entity lookup performance (< 1ms healthy, < 10ms degraded)
  - Measures index operation timing
  - Validates performance thresholds

  **Memory Usage:**
  - Monitors index memory consumption
  - Alerts on high usage (>100MB degraded, >500MB unhealthy)
  - Tracks memory efficiency per subscription

  **Subscription Counts:**
  - Monitors subscription volume
  - Alerts on high counts (>10k degraded, >50k unhealthy)
  - Tracks entity entry counts

  ## Integration

  Integrates seamlessly with the main application health checks via
  `ApplicationHealth`. Each entity type gets its own health check component
  while sharing the same underlying implementation.
  """

  alias WandererKills.Support.Clock

  defmacro __using__(opts) do
    index_module = Keyword.fetch!(opts, :index_module)
    entity_type = Keyword.fetch!(opts, :entity_type)
    entity_type_string = Atom.to_string(entity_type)
    component_name = "#{entity_type_string}_subscriptions"

    quote do
      @behaviour WandererKills.Observability.HealthCheckBehaviour

      require Logger

      @index_module unquote(index_module)
      @entity_type unquote(entity_type)
      @entity_type_string unquote(entity_type_string)
      @component_name unquote(component_name)

      @doc """
      Performs health checks for the #{unquote(entity_type)} subscription system.
      """
      @impl true
      def check_health(_opts \\ []) do
        WandererKills.Observability.SubscriptionHealth.check_health(
          @index_module,
          @entity_type,
          @entity_type_string,
          @component_name
        )
      end

      @doc """
      Retrieves metrics for the #{unquote(entity_type)} subscription system.
      """
      @impl true
      def get_metrics(_opts \\ []) do
        WandererKills.Observability.SubscriptionHealth.get_metrics(
          @index_module,
          @entity_type,
          @entity_type_string,
          @component_name
        )
      end

      @doc """
      Default configuration for #{unquote(entity_type)} subscription health checks.
      """
      @impl true
      def default_config do
        [timeout_ms: 5_000]
      end
    end
  end

  @doc """
  Shared implementation for health checking.
  """
  def check_health(index_module, _entity_type, entity_type_string, component_name) do
    _timestamp = DateTime.utc_now()

    checks = %{
      index_availability: check_index_availability(index_module),
      index_performance: check_index_performance(index_module, entity_type_string),
      memory_usage: check_memory_usage(index_module),
      subscription_counts: check_subscription_counts(index_module, entity_type_string)
    }

    metrics = collect_metrics(index_module, entity_type_string)
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

  @doc """
  Shared implementation for metrics collection.
  """
  def get_metrics(index_module, _entity_type, entity_type_string, component_name) do
    %{
      component: component_name,
      timestamp: Clock.now_iso8601(),
      metrics: collect_metrics(index_module, entity_type_string)
    }
  end

  # ============================================================================
  # Private Health Check Functions
  # ============================================================================

  defp check_index_availability(index_module) do
    try do
      stats = index_module.get_stats()

      if is_map(stats) and Map.has_key?(stats, :total_subscriptions) do
        %{
          status: :healthy,
          message: "#{inspect(index_module)} responding normally",
          response_time_ms: measure_response_time(index_module)
        }
      else
        %{
          status: :unhealthy,
          message: "#{inspect(index_module)} returning invalid stats",
          invalid_stats: inspect(stats)
        }
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "#{inspect(index_module)} not available: #{inspect(error)}",
          error_type: error.__struct__
        }
    end
  end

  defp check_index_performance(index_module, entity_type_string) do
    try do
      # Use entity-appropriate test ID
      test_entity_id = get_test_entity_id(entity_type_string)

      {time_microseconds, _result} =
        :timer.tc(fn ->
          index_module.find_subscriptions_for_entity(test_entity_id)
        end)

      cond do
        # > 10ms
        time_microseconds > 10_000 ->
          %{
            status: :unhealthy,
            message:
              "#{entity_type_string |> String.capitalize()} lookup took #{time_microseconds}μs (>10ms)",
            duration_us: time_microseconds,
            threshold: "10ms"
          }

        # > 1ms
        time_microseconds > 1_000 ->
          %{
            status: :degraded,
            message:
              "#{entity_type_string |> String.capitalize()} lookup took #{time_microseconds}μs (>1ms)",
            duration_us: time_microseconds,
            threshold: "1ms"
          }

        true ->
          %{
            status: :healthy,
            message: "#{entity_type_string |> String.capitalize()} lookup performance normal",
            duration_us: time_microseconds
          }
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Performance test failed: #{inspect(error)}",
          error_type: error.__struct__
        }
    end
  end

  defp check_memory_usage(index_module) do
    try do
      stats = index_module.get_stats()
      memory_bytes = Map.get(stats, :memory_usage_bytes, 0)
      memory_mb = Float.round(memory_bytes / (1024 * 1024), 2)

      cond do
        # > 500MB
        memory_mb > 500 ->
          %{
            status: :unhealthy,
            message: "Excessive memory usage: #{memory_mb}MB",
            memory_mb: memory_mb,
            threshold: "500MB"
          }

        # > 100MB
        memory_mb > 100 ->
          %{
            status: :degraded,
            message: "High memory usage: #{memory_mb}MB",
            memory_mb: memory_mb,
            threshold: "100MB"
          }

        true ->
          %{
            status: :healthy,
            message: "Memory usage normal: #{memory_mb}MB",
            memory_mb: memory_mb
          }
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Memory check failed: #{inspect(error)}",
          error_type: error.__struct__
        }
    end
  end

  defp check_subscription_counts(index_module, entity_type_string) do
    try do
      stats = index_module.get_stats()
      subscription_count = Map.get(stats, :total_subscriptions, 0)

      # Get entity-specific entry count
      entity_entries_key =
        case entity_type_string do
          "character" -> :total_character_entries
          "system" -> :total_system_entries
          _ -> :total_entity_entries
        end

      entity_entry_count = Map.get(stats, entity_entries_key, 0)

      cond do
        subscription_count > 50_000 ->
          %{
            status: :unhealthy,
            message: "Excessive subscription count: #{subscription_count}",
            subscription_count: subscription_count,
            entity_entry_count: entity_entry_count,
            threshold: "50k subscriptions"
          }

        subscription_count > 10_000 ->
          %{
            status: :degraded,
            message: "High subscription count: #{subscription_count}",
            subscription_count: subscription_count,
            entity_entry_count: entity_entry_count,
            threshold: "10k subscriptions"
          }

        true ->
          %{
            status: :healthy,
            message: "Subscription counts normal",
            subscription_count: subscription_count,
            entity_entry_count: entity_entry_count
          }
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Subscription count check failed: #{inspect(error)}",
          error_type: error.__struct__
        }
    end
  end

  defp collect_metrics(index_module, entity_type_string) do
    try do
      stats = index_module.get_stats()

      # Get entity-specific keys based on entity type
      {entity_entries_key, entity_subscriptions_key} =
        case entity_type_string do
          "character" -> {:total_character_entries, :total_character_subscriptions}
          "system" -> {:total_system_entries, :total_system_subscriptions}
          _ -> {:total_entity_entries, :total_entity_subscriptions}
        end

      %{
        total_subscriptions: Map.get(stats, :total_subscriptions, 0),
        total_entity_entries: Map.get(stats, entity_entries_key, 0),
        total_entity_subscriptions: Map.get(stats, entity_subscriptions_key, 0),
        memory_usage_bytes: Map.get(stats, :memory_usage_bytes, 0),
        memory_usage_mb: Float.round(Map.get(stats, :memory_usage_bytes, 0) / (1024 * 1024), 2),
        avg_entities_per_subscription:
          calculate_avg_entities_per_subscription(stats, entity_subscriptions_key),
        index_efficiency: calculate_index_efficiency(stats, entity_entries_key)
      }
    rescue
      _error ->
        %{
          total_subscriptions: 0,
          total_entity_entries: 0,
          total_entity_subscriptions: 0,
          memory_usage_bytes: 0,
          memory_usage_mb: 0.0,
          avg_entities_per_subscription: 0.0,
          index_efficiency: 0.0,
          error: "Failed to collect metrics"
        }
    end
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp determine_overall_status(checks) do
    statuses = checks |> Map.values() |> Enum.map(&Map.get(&1, :status))

    cond do
      :unhealthy in statuses -> :unhealthy
      :degraded in statuses -> :degraded
      true -> :healthy
    end
  end

  defp calculate_avg_entities_per_subscription(stats, entity_subscriptions_key) do
    subscription_count = Map.get(stats, :total_subscriptions, 0)
    entity_subscription_count = Map.get(stats, entity_subscriptions_key, 0)

    if subscription_count > 0 do
      Float.round(entity_subscription_count / subscription_count, 2)
    else
      0.0
    end
  end

  defp calculate_index_efficiency(stats, entity_entries_key) do
    subscription_count = Map.get(stats, :total_subscriptions, 0)
    entity_entry_count = Map.get(stats, entity_entries_key, 0)

    if subscription_count > 0 do
      # Efficiency = entity entries / subscriptions (lower is better, indicates good deduplication)
      Float.round(entity_entry_count / subscription_count, 2)
    else
      0.0
    end
  end

  defp measure_response_time(index_module) do
    {time_microseconds, _result} =
      :timer.tc(fn ->
        index_module.get_stats()
      end)

    # Convert to milliseconds
    Float.round(time_microseconds / 1000, 2)
  end

  defp get_test_entity_id(entity_type_string) do
    case entity_type_string do
      # Typical character ID
      "character" -> 123_456
      # Jita system ID
      "system" -> 30_000_142
      # Generic test ID
      _ -> 1
    end
  end
end
