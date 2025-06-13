defmodule WandererKills.Observability.SystemSubscriptionHealth do
  @moduledoc """
  Health check implementation for the system subscription system.

  Monitors the performance and health of system subscription components:
  - SystemIndex ETS table status and performance
  - System subscription counts and distribution
  - Memory usage of system indexing structures
  - Performance metrics for system-based filtering operations

  ## Health Metrics

  **System Index Health:**
  - ETS table availability and integrity
  - Memory usage within acceptable bounds
  - Subscription count within reasonable limits
  - Index operation performance

  **Performance Thresholds:**
  - System lookup operations should complete in < 1ms
  - Batch system lookups should scale linearly
  - Memory usage per subscription should be reasonable
  - Index cleanup should run successfully

  ## Integration

  This module is integrated into the main application health checks
  via `Observability.ApplicationHealth`. It provides system subscription
  specific monitoring to complement character subscription monitoring.
  """

  @behaviour WandererKills.Observability.HealthCheckBehaviour

  alias WandererKills.Subscriptions.SystemIndex
  require Logger

  @doc """
  Performs health checks for the system subscription system.

  Returns a map containing:
  - `:healthy` - Boolean indicating overall health
  - `:status` - String status 
  - `:details` - Individual check results and metrics
  - `:timestamp` - When the check was performed
  """
  @impl true
  def check_health(_opts \\ []) do
    timestamp = DateTime.utc_now()

    checks = %{
      index_availability: check_index_availability(),
      index_performance: check_index_performance(),
      memory_usage: check_memory_usage(),
      subscription_counts: check_subscription_counts()
    }

    metrics = collect_metrics()

    overall_status = determine_overall_status(checks)
    healthy = overall_status == :healthy

    %{
      healthy: healthy,
      status: Atom.to_string(overall_status),
      details: %{
        component: "system_subscriptions",
        checks: checks,
        metrics: metrics
      },
      timestamp: DateTime.to_iso8601(timestamp)
    }
  end

  @doc """
  Retrieves metrics for the system subscription system.
  """
  @impl true
  def get_metrics(_opts \\ []) do
    %{
      component: "system_subscriptions",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      metrics: collect_metrics()
    }
  end

  # Private functions

  defp check_index_availability do
    try do
      stats = SystemIndex.get_stats()

      if is_map(stats) and Map.has_key?(stats, :total_subscriptions) do
        %{status: :healthy, message: "SystemIndex responding normally"}
      else
        %{status: :unhealthy, message: "SystemIndex returning invalid stats"}
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "SystemIndex not available: #{inspect(error)}"
        }
    end
  end

  defp check_index_performance do
    try do
      # Test single system lookup performance
      test_system_id = 30_000_142

      {time_microseconds, _result} =
        :timer.tc(fn ->
          SystemIndex.find_subscriptions_for_system(test_system_id)
        end)

      cond do
        # > 10ms
        time_microseconds > 10_000 ->
          %{
            status: :unhealthy,
            message: "System lookup took #{time_microseconds}μs (>10ms)",
            duration_us: time_microseconds
          }

        # > 1ms
        time_microseconds > 1_000 ->
          %{
            status: :degraded,
            message: "System lookup took #{time_microseconds}μs (>1ms)",
            duration_us: time_microseconds
          }

        true ->
          %{
            status: :healthy,
            message: "System lookup performance normal",
            duration_us: time_microseconds
          }
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Performance test failed: #{inspect(error)}"
        }
    end
  end

  defp check_memory_usage do
    try do
      stats = SystemIndex.get_stats()
      memory_bytes = Map.get(stats, :memory_usage_bytes, 0)
      memory_mb = Float.round(memory_bytes / (1024 * 1024), 2)

      cond do
        # > 100MB
        memory_mb > 100 ->
          %{
            status: :degraded,
            message: "High memory usage: #{memory_mb}MB",
            memory_mb: memory_mb
          }

        # > 500MB
        memory_mb > 500 ->
          %{
            status: :unhealthy,
            message: "Excessive memory usage: #{memory_mb}MB",
            memory_mb: memory_mb
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
          message: "Memory check failed: #{inspect(error)}"
        }
    end
  end

  defp check_subscription_counts do
    try do
      stats = SystemIndex.get_stats()
      subscription_count = Map.get(stats, :total_subscriptions, 0)
      system_entry_count = Map.get(stats, :total_system_entries, 0)

      cond do
        subscription_count > 10_000 ->
          %{
            status: :degraded,
            message: "High subscription count: #{subscription_count}",
            subscription_count: subscription_count,
            system_entry_count: system_entry_count
          }

        subscription_count > 50_000 ->
          %{
            status: :unhealthy,
            message: "Excessive subscription count: #{subscription_count}",
            subscription_count: subscription_count,
            system_entry_count: system_entry_count
          }

        true ->
          %{
            status: :healthy,
            message: "Subscription counts normal",
            subscription_count: subscription_count,
            system_entry_count: system_entry_count
          }
      end
    rescue
      error ->
        %{
          status: :unhealthy,
          message: "Subscription count check failed: #{inspect(error)}"
        }
    end
  end

  defp collect_metrics do
    try do
      stats = SystemIndex.get_stats()

      %{
        total_subscriptions: Map.get(stats, :total_subscriptions, 0),
        total_system_entries: Map.get(stats, :total_system_entries, 0),
        memory_usage_bytes: Map.get(stats, :memory_usage_bytes, 0),
        memory_usage_mb: Float.round(Map.get(stats, :memory_usage_bytes, 0) / (1024 * 1024), 2),
        avg_systems_per_subscription: calculate_avg_systems_per_subscription(stats)
      }
    rescue
      _error ->
        %{
          total_subscriptions: 0,
          total_system_entries: 0,
          memory_usage_bytes: 0,
          memory_usage_mb: 0.0,
          avg_systems_per_subscription: 0.0
        }
    end
  end

  defp calculate_avg_systems_per_subscription(stats) do
    subscription_count = Map.get(stats, :total_subscriptions, 0)
    system_entry_count = Map.get(stats, :total_system_entries, 0)

    if subscription_count > 0 do
      Float.round(system_entry_count / subscription_count, 2)
    else
      0.0
    end
  end

  defp determine_overall_status(checks) do
    statuses = checks |> Map.values() |> Enum.map(&Map.get(&1, :status))

    cond do
      :unhealthy in statuses -> :unhealthy
      :degraded in statuses -> :degraded
      true -> :healthy
    end
  end
end
