defmodule WandererKills.Observability.HealthAggregator do
  @moduledoc """
  Aggregates health checks and metrics across multiple components.

  This module provides utilities for combining health status and metrics
  from different health check implementations into unified views.
  """

  require Logger
  alias WandererKills.Support.Clock

  @type health_component :: :application | :cache
  @type health_status :: map()
  @type metrics :: map()

  @doc """
  Aggregates health checks from multiple components.

  ## Parameters
  - `components` - List of component atoms to check
  - `timeout` - Timeout in milliseconds for each check

  ## Returns
  Aggregated health status with details from all components.
  """
  @spec aggregate_health([health_component()], pos_integer()) :: health_status()
  def aggregate_health(components, timeout) do
    component_results =
      Enum.map(components, fn component ->
        {component, check_component(component, timeout)}
      end)

    all_healthy = Enum.all?(component_results, fn {_comp, result} -> result.healthy end)

    %{
      healthy: all_healthy,
      status: determine_aggregate_status(component_results),
      details: %{
        component: "aggregate",
        components: Map.new(component_results),
        total_components: length(components),
        healthy_components:
          Enum.count(component_results, fn {_comp, result} -> result.healthy end)
      },
      timestamp: Clock.now_iso8601()
    }
  end

  @doc """
  Aggregates metrics from multiple components.

  ## Parameters
  - `components` - List of component atoms to collect metrics from
  - `timeout` - Timeout in milliseconds for each collection

  ## Returns
  Aggregated metrics with data from all components.
  """
  @spec aggregate_metrics([health_component()], pos_integer()) :: metrics()
  def aggregate_metrics(components, timeout) do
    component_metrics =
      Enum.map(components, fn component ->
        {component, get_component_metrics(component, timeout)}
      end)

    %{
      component: "aggregate",
      timestamp: Clock.now_iso8601(),
      metrics: %{
        components: Map.new(component_metrics),
        total_components: length(components)
      }
    }
  end

  # Private functions

  @spec check_component(health_component(), pos_integer()) :: health_status()
  defp check_component(component, timeout) do
    module = get_health_module(component)
    
    case safe_check_health(module, timeout: timeout) do
      {:ok, health} ->
        health

      {:error, _reason} ->
        %{
          healthy: false,
          status: "error",
          details: %{component: to_string(component)},
          timestamp: Clock.now_iso8601()
        }
    end
  end

  @spec get_component_metrics(health_component(), pos_integer()) :: metrics()
  defp get_component_metrics(component, timeout) do
    module = get_health_module(component)
    
    case safe_get_metrics(module, timeout: timeout) do
      {:ok, metrics} ->
        metrics

      {:error, _reason} ->
        %{
          component: to_string(component),
          timestamp: Clock.now_iso8601(),
          metrics: %{error: "Failed to collect metrics"}
        }
    end
  end

  @spec get_health_module(health_component()) :: module()
  defp get_health_module(:application), do: WandererKills.Observability.ApplicationHealth
  defp get_health_module(:cache), do: WandererKills.Observability.CacheHealth

  @spec safe_check_health(module(), keyword()) :: {:ok, health_status()} | {:error, term()}
  defp safe_check_health(module, opts) do
    health_status = module.check_health(opts)
    {:ok, health_status}
  rescue
    error ->
      Logger.error("Health check failed for #{inspect(module)}: #{inspect(error)}")
      {:error, error}
  end

  @spec safe_get_metrics(module(), keyword()) :: {:ok, metrics()} | {:error, term()}
  defp safe_get_metrics(module, opts) do
    metrics = module.get_metrics(opts)
    {:ok, metrics}
  rescue
    error ->
      Logger.error("Metrics collection failed for #{inspect(module)}: #{inspect(error)}")
      {:error, error}
  end

  @spec determine_aggregate_status([{health_component(), health_status()}]) :: String.t()
  defp determine_aggregate_status(component_results) do
    healthy_count = Enum.count(component_results, fn {_comp, result} -> result.healthy end)
    total_count = length(component_results)

    cond do
      healthy_count == total_count -> "ok"
      healthy_count == 0 -> "critical"
      healthy_count < total_count / 2 -> "degraded"
      true -> "warning"
    end
  end
end