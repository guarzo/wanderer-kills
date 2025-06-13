defmodule WandererKills.Observability.HealthChecks do
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

  alias WandererKills.Observability.{
    ApplicationHealth,
    CacheHealth,
    CharacterSubscriptionHealth,
    HealthAggregator
  }

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

    case components do
      [:application] ->
        case check_application_health(timeout: timeout) do
          {:ok, health} ->
            health

          {:error, _reason} ->
            %{
              healthy: false,
              status: "error",
              details: %{component: "application"},
              timestamp: WandererKills.Support.Clock.now_iso8601()
            }
        end

      [:cache] ->
        case check_cache_health(timeout: timeout) do
          {:ok, health} ->
            health

          {:error, _reason} ->
            %{
              healthy: false,
              status: "error",
              details: %{component: "cache"},
              timestamp: WandererKills.Support.Clock.now_iso8601()
            }
        end

      [:character_subscriptions] ->
        case check_character_subscription_health(timeout: timeout) do
          {:ok, health} ->
            health

          {:error, _reason} ->
            %{
              healthy: false,
              status: "error",
              details: %{component: "character_subscriptions"},
              timestamp: WandererKills.Support.Clock.now_iso8601()
            }
        end

      multiple_components when is_list(multiple_components) ->
        HealthAggregator.aggregate_health(multiple_components, timeout)

      _single_component ->
        %{
          healthy: false,
          status: "error",
          details: %{error: "Invalid component specification"},
          timestamp: WandererKills.Support.Clock.now_iso8601()
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

    case components do
      [:application] ->
        case get_application_metrics(timeout: timeout) do
          {:ok, metrics} ->
            metrics

          {:error, _reason} ->
            %{
              component: "application",
              timestamp: WandererKills.Support.Clock.now_iso8601(),
              metrics: %{error: "Failed to collect metrics"}
            }
        end

      [:cache] ->
        case get_cache_metrics(timeout: timeout) do
          {:ok, metrics} ->
            metrics

          {:error, _reason} ->
            %{
              component: "cache",
              timestamp: WandererKills.Support.Clock.now_iso8601(),
              metrics: %{error: "Failed to collect metrics"}
            }
        end

      [:character_subscriptions] ->
        case get_character_subscription_metrics(timeout: timeout) do
          {:ok, metrics} ->
            metrics

          {:error, _reason} ->
            %{
              component: "character_subscriptions",
              timestamp: WandererKills.Support.Clock.now_iso8601(),
              metrics: %{error: "Failed to collect metrics"}
            }
        end

      multiple_components when is_list(multiple_components) ->
        HealthAggregator.aggregate_metrics(multiple_components, timeout)

      _single_component ->
        %{
          component: "unknown",
          timestamp: WandererKills.Support.Clock.now_iso8601(),
          metrics: %{error: "Invalid component specification"}
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
