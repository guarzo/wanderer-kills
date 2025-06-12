defmodule WandererKills.Observability.HealthCheckBehaviour do
  @moduledoc """
  Behaviour definition for health check implementations.

  All health checks should return a consistent status structure and
  implement the required callbacks for checking health and retrieving metrics.
  """

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
end
