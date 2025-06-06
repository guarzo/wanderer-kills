defmodule WandererKills.Observability.HealthChecks.ApplicationHealth do
  @moduledoc """
  Application-level health check that aggregates all component health checks.

  This module provides a unified view of application health by collecting
  and aggregating health status from all registered health check modules.
  """

  @behaviour WandererKills.Observability.Behaviours.HealthCheck

  require Logger
  alias WandererKills.Clock
  alias WandererKills.Observability.HealthChecks.CacheHealth

  @impl true
  def check_health(opts \\ []) do
    config = Keyword.merge(default_config(), opts)
    health_modules = Keyword.get(config, :health_modules)

    component_checks = Enum.map(health_modules, &run_component_health_check/1)
    all_healthy = Enum.all?(component_checks, & &1.healthy)

    %{
      healthy: all_healthy,
      status: determine_overall_status(component_checks),
      details: %{
        component: "application",
        version: get_application_version(),
        uptime_seconds: get_uptime_seconds(),
        components: component_checks,
        total_components: length(health_modules),
        healthy_components: Enum.count(component_checks, & &1.healthy)
      },
      timestamp: Clock.now_iso8601()
    }
  end

  @impl true
  def get_metrics(opts \\ []) do
    config = Keyword.merge(default_config(), opts)
    health_modules = Keyword.get(config, :health_modules)

    component_metrics = Enum.map(health_modules, &run_component_metrics/1)

    %{
      component: "application",
      timestamp: Clock.now_iso8601(),
      metrics: %{
        version: get_application_version(),
        uptime_seconds: get_uptime_seconds(),
        total_components: length(health_modules),
        components: component_metrics,
        system: get_system_metrics()
      }
    }
  end

  @impl true
  def default_config do
    [
      health_modules: [
        CacheHealth
      ],
      timeout_ms: 10_000,
      include_system_metrics: true
    ]
  end

  # Private helper functions

  @spec run_component_health_check(module()) :: map()
  defp run_component_health_check(health_module) do
    try do
      health_module.check_health()
    rescue
      error ->
        Logger.error("Health check failed for #{inspect(health_module)}: #{inspect(error)}")

        %{
          healthy: false,
          status: "error",
          details: %{
            component: inspect(health_module),
            error: "Health check failed",
            reason: inspect(error)
          },
          timestamp: Clock.now_iso8601()
        }
    end
  end

  @spec run_component_metrics(module()) :: map()
  defp run_component_metrics(health_module) do
    try do
      health_module.get_metrics()
    rescue
      error ->
        Logger.error("Metrics collection failed for #{inspect(health_module)}: #{inspect(error)}")

        %{
          component: inspect(health_module),
          timestamp: Clock.now_iso8601(),
          metrics: %{
            error: "Metrics collection failed",
            reason: inspect(error)
          }
        }
    end
  end

  @spec determine_overall_status([map()]) :: String.t()
  defp determine_overall_status(component_checks) do
    healthy_count = Enum.count(component_checks, & &1.healthy)
    total_count = length(component_checks)

    cond do
      healthy_count == total_count -> "ok"
      healthy_count == 0 -> "critical"
      healthy_count < total_count / 2 -> "degraded"
      true -> "warning"
    end
  end

  @spec get_application_version() :: String.t()
  defp get_application_version do
    case Application.spec(:wanderer_kills, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  @spec get_uptime_seconds() :: non_neg_integer()
  defp get_uptime_seconds do
    :erlang.statistics(:wall_clock)
    |> elem(0)
    |> div(1000)
  end

  @spec get_system_metrics() :: map()
  defp get_system_metrics do
    try do
      %{
        memory_usage: :erlang.memory(),
        process_count: :erlang.system_info(:process_count),
        port_count: :erlang.system_info(:port_count),
        ets_tables: length(:ets.all()),
        schedulers: :erlang.system_info(:schedulers),
        run_queue: :erlang.statistics(:run_queue)
      }
    rescue
      error ->
        Logger.warning("Failed to collect system metrics: #{inspect(error)}")
        %{error: "System metrics collection failed"}
    end
  end
end
