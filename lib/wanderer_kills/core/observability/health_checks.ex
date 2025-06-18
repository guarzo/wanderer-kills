defmodule WandererKills.Core.Observability.HealthChecks do
  @moduledoc """
  Unified interface for health checks and metrics collection.

  This module provides a simplified API for health checking and metrics
  collection, delegating to specialized modules for implementation details.

  ## Architecture

  - `HealthCheckBehaviour` - Defines the contract for health check implementations
  - `ApplicationHealth` - Checks overall application health
  - `CacheHealth` - Checks cache system health
  - `HealthAggregator` - Combines health checks from multiple components

  ## Usage

  ```elixir
  # Get comprehensive application health
  health_status = HealthChecks.check_health()

  # Get application metrics
  metrics = HealthChecks.get_metrics()

  # Get health for specific components
  cache_health = HealthChecks.check_health(components: [:cache])
  ```
  """

  require Logger

  alias WandererKills.Core.Observability.{
    ApplicationHealth,
    CacheHealth,
    CharacterSubscriptionHealth,
    HealthAggregator
  }

  alias WandererKills.Core.Support.Clock

  @type health_opts :: keyword()
  @type health_component :: :application | :cache | :character_subscriptions

  # ============================================================================
  # Public API
  # ============================================================================

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
  health = HealthChecks.check_health()

  # Only cache health
  cache_health = HealthChecks.check_health(components: [:cache])

  # Multiple components
  health = HealthChecks.check_health(components: [:application, :cache])
  ```
  """
  @spec check_health(health_opts()) :: map()
  def check_health(opts \\ []) do
    components = Keyword.get(opts, :components, [:application])
    timeout = Keyword.get(opts, :timeout, 10_000)

    handle_health_check_request(components, timeout)
  end

  # Map of component atoms to their health check functions
  @health_check_functions %{
    application: &__MODULE__.check_application_health/1,
    cache: &__MODULE__.check_cache_health/1,
    character_subscriptions: &__MODULE__.check_character_subscription_health/1
  }

  # Map of component atoms to their metrics functions
  @metrics_functions %{
    application: &__MODULE__.get_application_metrics/1,
    cache: &__MODULE__.get_cache_metrics/1,
    character_subscriptions: &__MODULE__.get_character_subscription_metrics/1
  }

  defp handle_health_check_request([component], timeout) when is_atom(component) do
    case Map.get(@health_check_functions, component) do
      nil -> {:error, %{healthy: false, error: "Unknown component: #{component}"}}
      check_fn -> check_single_component_health(component, timeout, check_fn)
    end
  end

  defp handle_health_check_request(components, timeout) when is_list(components) do
    HealthAggregator.aggregate_health(components, timeout)
  end

  defp handle_health_check_request(_invalid_components, _timeout) do
    %{
      healthy: false,
      status: "error",
      details: %{error: "Invalid component specification"},
      timestamp: Clock.now_iso8601()
    }
  end

  defp check_single_component_health(component, timeout, checker_fn) do
    case checker_fn.(timeout: timeout) do
      {:ok, health} ->
        health

      {:error, reason} ->
        require Logger
        Logger.warning("Health check failed for component #{component}: #{inspect(reason)}")

        %{
          healthy: false,
          status: "error",
          details: %{
            component: Atom.to_string(component),
            error_reason: inspect(reason)
          },
          timestamp: Clock.now_iso8601()
        }
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
  metrics = HealthChecks.get_metrics()

  # Only cache metrics
  cache_metrics = HealthChecks.get_metrics(components: [:cache])
  ```
  """
  @spec get_metrics(health_opts()) :: map()
  def get_metrics(opts \\ []) do
    components = Keyword.get(opts, :components, [:application])
    timeout = Keyword.get(opts, :timeout, 10_000)

    handle_metrics_request(components, timeout)
  end

  defp handle_metrics_request([component], timeout) when is_atom(component) do
    case Map.get(@metrics_functions, component) do
      nil -> {:error, "Unknown component: #{component}"}
      metrics_fn -> get_single_component_metrics(component, timeout, metrics_fn)
    end
  end

  defp handle_metrics_request(components, timeout) when is_list(components) do
    HealthAggregator.aggregate_metrics(components, timeout)
  end

  defp handle_metrics_request(_invalid_components, _timeout) do
    %{
      component: "unknown",
      timestamp: Clock.now_iso8601(),
      metrics: %{error: "Invalid component specification"}
    }
  end

  defp get_single_component_metrics(component, timeout, fetcher_fn) do
    case fetcher_fn.(timeout: timeout) do
      {:ok, metrics} ->
        metrics

      {:error, reason} ->
        require Logger
        Logger.warning("Metrics collection failed for component #{component}: #{inspect(reason)}")

        %{
          component: Atom.to_string(component),
          timestamp: Clock.now_iso8601(),
          metrics: %{
            error: "Failed to collect metrics",
            error_reason: inspect(reason)
          }
        }
    end
  end

  @doc """
  Checks overall application health by aggregating all component health checks.

  ## Options
  - `:health_modules` - List of health check modules to run (default: all registered)
  - `:timeout_ms` - Timeout for health checks (default: 10_000)
  - `:include_system_metrics` - Include system metrics (default: true)

  ## Returns
  - `{:ok, health_status}` - Application health status
  - `{:error, reason}` - If health check fails
  """
  @spec check_application_health(health_opts()) :: {:ok, map()} | {:error, term()}
  def check_application_health(opts \\ []) do
    health_status = ApplicationHealth.check_health(opts)
    {:ok, health_status}
  rescue
    error ->
      Logger.error("Application health check failed: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Checks cache system health for all registered caches.

  ## Options
  - `:cache_names` - List of cache names to check (default: all configured caches)
  - `:include_stats` - Include cache statistics (default: true)
  - `:timeout_ms` - Timeout for cache checks (default: 5_000)

  ## Returns
  - `{:ok, health_status}` - Cache system health status
  - `{:error, reason}` - If health check fails
  """
  @spec check_cache_health(health_opts()) :: {:ok, map()} | {:error, term()}
  def check_cache_health(opts \\ []) do
    health_status = CacheHealth.check_health(opts)
    {:ok, health_status}
  rescue
    error ->
      Logger.error("Cache health check failed: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Gets comprehensive application metrics including all components.

  ## Options
  - `:health_modules` - List of health check modules to collect metrics from
  - `:include_system_metrics` - Include system metrics (default: true)

  ## Returns
  - `{:ok, metrics}` - Application metrics
  - `{:error, reason}` - If metrics collection fails
  """
  @spec get_application_metrics(health_opts()) :: {:ok, map()} | {:error, term()}
  def get_application_metrics(opts \\ []) do
    metrics = ApplicationHealth.get_metrics(opts)
    {:ok, metrics}
  rescue
    error ->
      Logger.error("Application metrics collection failed: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Gets cache system metrics for all registered caches.

  ## Options
  - `:cache_names` - List of cache names to collect metrics from
  - `:include_stats` - Include detailed cache statistics (default: true)

  ## Returns
  - `{:ok, metrics}` - Cache system metrics
  - `{:error, reason}` - If metrics collection fails
  """
  @spec get_cache_metrics(health_opts()) :: {:ok, map()} | {:error, term()}
  def get_cache_metrics(opts \\ []) do
    metrics = CacheHealth.get_metrics(opts)
    {:ok, metrics}
  rescue
    error ->
      Logger.error("Cache metrics collection failed: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Checks character subscription system health.

  ## Options
  - `:timeout` - Timeout for health checks (default: 5_000)

  ## Returns
  - `{:ok, health_status}` - Character subscription system health status
  - `{:error, reason}` - If health check fails
  """
  @spec check_character_subscription_health(health_opts()) :: {:ok, map()} | {:error, term()}
  def check_character_subscription_health(opts \\ []) do
    health_status = CharacterSubscriptionHealth.check_health(opts)
    {:ok, health_status}
  rescue
    error ->
      Logger.error("Character subscription health check failed: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Gets character subscription system metrics.

  ## Options
  - `:timeout` - Timeout for metrics collection (default: 5_000)

  ## Returns
  - `{:ok, metrics}` - Character subscription system metrics
  - `{:error, reason}` - If metrics collection fails
  """
  @spec get_character_subscription_metrics(health_opts()) :: {:ok, map()} | {:error, term()}
  def get_character_subscription_metrics(opts \\ []) do
    metrics = CharacterSubscriptionHealth.get_metrics(opts)
    {:ok, metrics}
  rescue
    error ->
      Logger.error("Character subscription metrics collection failed: #{inspect(error)}")
      {:error, error}
  end
end
