defmodule WandererKills.Infrastructure.Health do
  @moduledoc """
  Main health check module for the WandererKills application.

  This module provides a unified interface for health checking and metrics
  collection, delegating to standardized health check implementations.

  ## Usage

  ```elixir
  # Get comprehensive application health
  health_status = Health.check_health()

  # Get application metrics
  metrics = Health.get_metrics()

  # Get health for specific components
  cache_health = Health.check_health(components: [:cache])
  ```

  ## Health Status Format

  All health checks return a consistent format:

  ```elixir
  %{
    healthy: boolean(),
    status: "ok" | "warning" | "degraded" | "critical",
    details: %{...},
    timestamp: "2025-01-01T00:00:00Z"
  }
  ```
  """

  require Logger
  alias WandererKills.Infrastructure.HealthChecks.{ApplicationHealth, CacheHealth}

  @type health_component :: :application | :cache
  @type health_opts :: [
          components: [health_component()],
          timeout: pos_integer()
        ]

  @doc """
  Performs a comprehensive health check of the application.

  ## Options
  - `:components` - List of specific components to check (default: [:application])
  - `:timeout` - Timeout for health checks in milliseconds (default: 10_000)

  ## Returns
  A health status map with comprehensive application health information.

  ## Examples

  ```elixir
  # Full application health
  health = Health.check_health()

  # Only cache health
  cache_health = Health.check_health(components: [:cache])

  # Multiple components
  health = Health.check_health(components: [:application, :cache])
  ```
  """
  @spec check_health(health_opts()) :: map()
  def check_health(opts \\ []) do
    components = Keyword.get(opts, :components, [:application])
    timeout = Keyword.get(opts, :timeout, 10_000)

    case components do
      [:application] ->
        ApplicationHealth.check_health(timeout: timeout)

      [:cache] ->
        CacheHealth.check_health(timeout: timeout)

      multiple_components when is_list(multiple_components) ->
        aggregate_component_health(multiple_components, timeout)

      single_component ->
        check_single_component(single_component, timeout)
    end
  end

  @doc """
  Gets application metrics including component-specific metrics.

  ## Options
  - `:components` - List of specific components to get metrics for (default: [:application])
  - `:timeout` - Timeout for metrics collection in milliseconds (default: 10_000)

  ## Returns
  A metrics map with detailed performance and operational metrics.

  ## Examples

  ```elixir
  # Full application metrics
  metrics = Health.get_metrics()

  # Only cache metrics
  cache_metrics = Health.get_metrics(components: [:cache])
  ```
  """
  @spec get_metrics(health_opts()) :: map()
  def get_metrics(opts \\ []) do
    components = Keyword.get(opts, :components, [:application])
    timeout = Keyword.get(opts, :timeout, 10_000)

    case components do
      [:application] ->
        ApplicationHealth.get_metrics(timeout: timeout)

      [:cache] ->
        CacheHealth.get_metrics(timeout: timeout)

      multiple_components when is_list(multiple_components) ->
        aggregate_component_metrics(multiple_components, timeout)

      single_component ->
        get_single_component_metrics(single_component, timeout)
    end
  end

  @doc """
  Backwards compatibility: Get basic application version.

  Use `check_health/1` for full health information.
  """
  @spec version() :: String.t()
  def version do
    case Application.spec(:wanderer_kills, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end

  # Private helper functions

  @spec aggregate_component_health([health_component()], pos_integer()) :: map()
  defp aggregate_component_health(components, timeout) do
    component_results =
      Enum.map(components, fn component ->
        {component, check_single_component(component, timeout)}
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
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @spec aggregate_component_metrics([health_component()], pos_integer()) :: map()
  defp aggregate_component_metrics(components, timeout) do
    component_metrics =
      Enum.map(components, fn component ->
        {component, get_single_component_metrics(component, timeout)}
      end)

    %{
      component: "aggregate",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      metrics: %{
        components: Map.new(component_metrics),
        total_components: length(components)
      }
    }
  end

  @spec check_single_component(health_component(), pos_integer()) :: map()
  defp check_single_component(component, timeout) do
    case component do
      :application ->
        ApplicationHealth.check_health(timeout: timeout)

      :cache ->
        CacheHealth.check_health(timeout: timeout)

      unknown ->
        Logger.warning("Unknown health component: #{inspect(unknown)}")

        %{
          healthy: false,
          status: "error",
          details: %{
            component: inspect(unknown),
            error: "Unknown component"
          },
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
    end
  end

  @spec get_single_component_metrics(health_component(), pos_integer()) :: map()
  defp get_single_component_metrics(component, timeout) do
    case component do
      :application ->
        ApplicationHealth.get_metrics(timeout: timeout)

      :cache ->
        CacheHealth.get_metrics(timeout: timeout)

      unknown ->
        Logger.warning("Unknown metrics component: #{inspect(unknown)}")

        %{
          component: inspect(unknown),
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          metrics: %{error: "Unknown component"}
        }
    end
  end

  @spec determine_aggregate_status([{health_component(), map()}]) :: String.t()
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
