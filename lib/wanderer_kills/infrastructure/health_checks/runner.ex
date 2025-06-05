defmodule WandererKills.Infrastructure.HealthChecks.Runner do
  @moduledoc """
  Health check runner that executes multiple health checks in parallel
  and aggregates the results.
  """

  alias WandererKills.Infrastructure.HealthChecks.HealthCheckBehaviour

  @type health_check_module :: module()
  @type aggregate_status :: :healthy | :unhealthy | :degraded
  @type health_report :: %{
          status: aggregate_status(),
          checks: [HealthCheckBehaviour.check_result()],
          summary: %{
            total: non_neg_integer(),
            healthy: non_neg_integer(),
            degraded: non_neg_integer(),
            unhealthy: non_neg_integer()
          },
          timestamp: DateTime.t(),
          duration_ms: non_neg_integer()
        }

  @doc """
  Runs all configured health checks and returns an aggregate report.
  """
  @spec run_all_checks() :: health_report()
  def run_all_checks do
    check_modules = get_health_check_modules()
    run_checks(check_modules)
  end

  @doc """
  Runs the specified health check modules and returns an aggregate report.
  """
  @spec run_checks([health_check_module()]) :: health_report()
  def run_checks(modules) when is_list(modules) do
    start_time = System.monotonic_time(:millisecond)

    # Execute all checks in parallel
    tasks =
      modules
      |> Enum.map(fn module ->
        Task.async(fn ->
          HealthCheckBehaviour.execute_check(module)
        end)
      end)

    # Collect results with timeout
    results =
      tasks
      |> Enum.map(&Task.await(&1, 10_000))  # 10 second timeout for all checks

    duration = System.monotonic_time(:millisecond) - start_time

    # Calculate summary
    summary = calculate_summary(results)
    overall_status = determine_overall_status(summary)

    %{
      status: overall_status,
      checks: results,
      summary: summary,
      timestamp: DateTime.utc_now(),
      duration_ms: duration
    }
  end

  @doc """
  Gets the list of health check modules from configuration.
  """
  def get_health_check_modules do
    Application.get_env(:wanderer_kills, :health_checks, [
      WandererKills.Infrastructure.HealthChecks.ApplicationHealth,
      WandererKills.Infrastructure.HealthChecks.CacheHealth
    ])
  end

  # Private helper functions

  defp calculate_summary(results) do
    counts =
      results
      |> Enum.reduce(%{healthy: 0, degraded: 0, unhealthy: 0}, fn result, acc ->
        Map.update!(acc, result.status, &(&1 + 1))
      end)

    Map.put(counts, :total, length(results))
  end

  defp determine_overall_status(%{unhealthy: unhealthy, degraded: degraded}) do
    cond do
      unhealthy > 0 -> :unhealthy
      degraded > 0 -> :degraded
      true -> :healthy
    end
  end
end
