defmodule WandererKills.Observability.HealthChecks do
  @moduledoc """
  Consolidated health checks context for WandererKills observability.

  This module provides a unified interface for all health check functionality,
  including behaviour definitions and implementations for application and cache health.

  ## Health Check Behaviour

  All health checks should return a consistent status structure:

  ```elixir
  %{
    healthy: boolean(),
    status: String.t(),
    details: map(),
    timestamp: String.t()
  }
  ```

  ## Usage

  ```elixir
  # Check overall application health
  {:ok, health} = HealthChecks.check_application_health()

  # Check cache system health
  {:ok, cache_health} = HealthChecks.check_cache_health()

  # Get application metrics
  {:ok, metrics} = HealthChecks.get_application_metrics()
  ```
  """

  require Logger
  alias WandererKills.Core.{Clock, Config}

  # ============================================================================
  # Health Check Behaviour Definition
  # ============================================================================

  @type health_status :: %{
          healthy: boolean(),
          status: String.t(),
          details: map(),
          timestamp: String.t()
        }

  @type metrics :: %{
          component: String.t(),
          timestamp: String.t(),
          metrics: map()
        }

  @type health_opts :: keyword()

  @doc """
  Performs a health check for the component.

  ## Parameters
  - `opts` - Optional configuration for the health check

  ## Returns
  A health status map containing:
  - `:healthy` - Boolean indicating if the component is healthy
  - `:status` - String status ("ok", "error", "degraded", etc.)
  - `:details` - Map with additional details about the health check
  - `:timestamp` - ISO8601 timestamp of when the check was performed
  """
  @callback check_health(health_opts()) :: health_status()

  @doc """
  Retrieves metrics for the component.

  ## Parameters
  - `opts` - Optional configuration for metrics collection

  ## Returns
  A metrics map containing:
  - `:component` - String identifying the component
  - `:timestamp` - ISO8601 timestamp of when metrics were collected
  - `:metrics` - Map containing component-specific metrics
  """
  @callback get_metrics(health_opts()) :: metrics()

  @doc """
  Optional callback for component-specific configuration.

  Components can implement this to provide default configuration
  that can be overridden by passed options.

  ## Returns
  Default configuration as a keyword list
  """
  @callback default_config() :: keyword()

  @optional_callbacks [default_config: 0]

  # ============================================================================
  # Public API
  # ============================================================================

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
  @spec check_application_health(health_opts()) :: {:ok, health_status()} | {:error, term()}
  def check_application_health(opts \\ []) do
    try do
      health_status = __MODULE__.ApplicationHealth.check_health(opts)
      {:ok, health_status}
    rescue
      error ->
        Logger.error("Application health check failed: #{inspect(error)}")
        {:error, error}
    end
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
  @spec check_cache_health(health_opts()) :: {:ok, health_status()} | {:error, term()}
  def check_cache_health(opts \\ []) do
    try do
      health_status = __MODULE__.CacheHealth.check_health(opts)
      {:ok, health_status}
    rescue
      error ->
        Logger.error("Cache health check failed: #{inspect(error)}")
        {:error, error}
    end
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
  @spec get_application_metrics(health_opts()) :: {:ok, metrics()} | {:error, term()}
  def get_application_metrics(opts \\ []) do
    try do
      metrics = __MODULE__.ApplicationHealth.get_metrics(opts)
      {:ok, metrics}
    rescue
      error ->
        Logger.error("Application metrics collection failed: #{inspect(error)}")
        {:error, error}
    end
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
  @spec get_cache_metrics(health_opts()) :: {:ok, metrics()} | {:error, term()}
  def get_cache_metrics(opts \\ []) do
    try do
      metrics = __MODULE__.CacheHealth.get_metrics(opts)
      {:ok, metrics}
    rescue
      error ->
        Logger.error("Cache metrics collection failed: #{inspect(error)}")
        {:error, error}
    end
  end

  # ============================================================================
  # Application Health Implementation
  # ============================================================================

  defmodule ApplicationHealth do
    @moduledoc """
    Application-level health check that aggregates all component health checks.

    This module provides a unified view of application health by collecting
    and aggregating health status from all registered health check modules.
    """

    @behaviour WandererKills.Observability.HealthChecks

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
          WandererKills.Observability.HealthChecks.CacheHealth
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
          Logger.error(
            "Metrics collection failed for #{inspect(health_module)}: #{inspect(error)}"
          )

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

  # ============================================================================
  # Cache Health Implementation
  # ============================================================================

  defmodule CacheHealth do
    @moduledoc """
    Health check implementation for cache systems.

    This module provides comprehensive health checking for all cache
    instances in the application, including size, connectivity, and
    performance metrics.
    """

    @behaviour WandererKills.Observability.HealthChecks

    @impl true
    def check_health(opts \\ []) do
      config = Keyword.merge(default_config(), opts)
      cache_names = Keyword.get(config, :cache_names)

      cache_checks = Enum.map(cache_names, &check_cache_health/1)
      all_healthy = Enum.all?(cache_checks, & &1.healthy)

      %{
        healthy: all_healthy,
        status: if(all_healthy, do: "ok", else: "error"),
        details: %{
          component: "cache_system",
          caches: cache_checks,
          total_caches: length(cache_names),
          healthy_caches: Enum.count(cache_checks, & &1.healthy)
        },
        timestamp: Clock.now_iso8601()
      }
    end

    @impl true
    def get_metrics(opts \\ []) do
      config = Keyword.merge(default_config(), opts)
      cache_names = Keyword.get(config, :cache_names)

      cache_metrics = Enum.map(cache_names, &get_cache_metrics/1)

      %{
        component: "cache_system",
        timestamp: Clock.now_iso8601(),
        metrics: %{
          total_caches: length(cache_names),
          caches: cache_metrics,
          aggregate: calculate_aggregate_metrics(cache_metrics)
        }
      }
    end

    @impl true
    def default_config do
      cache_names = [
        Config.cache_killmails_name(),
        Config.cache_system_name(),
        Config.cache_esi_name()
      ]

      [
        cache_names: cache_names,
        include_stats: true,
        timeout_ms: 5_000
      ]
    end

    # Private helper functions

    @spec check_cache_health(atom()) :: %{healthy: boolean(), name: atom(), status: String.t()}
    defp check_cache_health(cache_name) do
      try do
        case Cachex.size(cache_name) do
          {:ok, size} ->
            %{
              healthy: true,
              name: cache_name,
              status: "ok",
              size: size
            }

          {:error, reason} ->
            %{
              healthy: false,
              name: cache_name,
              status: "error",
              error: inspect(reason)
            }
        end
      rescue
        error ->
          Logger.warning("Cache health check failed for #{cache_name}: #{inspect(error)}")

          %{
            healthy: false,
            name: cache_name,
            status: "unavailable",
            error: inspect(error)
          }
      end
    end

    @spec get_cache_metrics(atom()) :: map()
    defp get_cache_metrics(cache_name) do
      base_metrics = %{name: cache_name}

      try do
        case Cachex.stats(cache_name) do
          {:ok, stats} ->
            Map.merge(base_metrics, %{
              size: Map.get(stats, :size, 0),
              hit_rate: Map.get(stats, :hit_rate, 0.0),
              miss_rate: Map.get(stats, :miss_rate, 0.0),
              eviction_count: Map.get(stats, :eviction_count, 0),
              expiration_count: Map.get(stats, :expiration_count, 0),
              update_count: Map.get(stats, :update_count, 0)
            })

          {:error, reason} ->
            Map.merge(base_metrics, %{
              error: "Unable to retrieve stats",
              reason: inspect(reason)
            })
        end
      rescue
        error ->
          Map.merge(base_metrics, %{
            error: "Stats collection failed",
            reason: inspect(error)
          })
      end
    end

    @spec calculate_aggregate_metrics([map()]) :: map()
    defp calculate_aggregate_metrics(cache_metrics) do
      valid_metrics = Enum.reject(cache_metrics, &Map.has_key?(&1, :error))

      if Enum.empty?(valid_metrics) do
        %{error: "No valid cache metrics available"}
      else
        %{
          total_size: Enum.sum(Enum.map(valid_metrics, &Map.get(&1, :size, 0))),
          average_hit_rate: calculate_average_hit_rate(valid_metrics),
          total_evictions: Enum.sum(Enum.map(valid_metrics, &Map.get(&1, :eviction_count, 0))),
          total_expirations: Enum.sum(Enum.map(valid_metrics, &Map.get(&1, :expiration_count, 0)))
        }
      end
    end

    @spec calculate_average_hit_rate([map()]) :: float()
    defp calculate_average_hit_rate(valid_metrics) do
      hit_rates = Enum.map(valid_metrics, &Map.get(&1, :hit_rate, 0.0))

      case hit_rates do
        [] -> 0.0
        rates -> Enum.sum(rates) / length(rates)
      end
    end
  end
end
