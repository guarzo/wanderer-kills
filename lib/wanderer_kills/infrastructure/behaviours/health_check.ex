defmodule WandererKills.Infrastructure.Behaviours.HealthCheck do
  @moduledoc """
  Behaviour for health check implementations.

  This behaviour standardizes health check functionality across the application,
  ensuring consistent status reporting and monitoring capabilities.

  ## Health Status

  All health checks should return a consistent status structure:

  ```elixir
  %{
    healthy: boolean(),
    status: String.t(),
    details: map(),
    timestamp: String.t()
  }
  ```

  ## Implementation Example

  ```elixir
  defmodule MyApp.SomeHealthCheck do
    @behaviour WandererKills.Infrastructure.Behaviours.HealthCheck

    @impl true
    def check_health(opts \\\\ []) do
      case perform_health_check() do
        :ok ->
          %{
            healthy: true,
            status: "ok",
            details: %{component: "some_service"},
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }

        {:error, reason} ->
          %{
            healthy: false,
            status: "error",
            details: %{component: "some_service", error: reason},
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }
      end
    end

    @impl true
    def get_metrics(opts \\\\ []) do
      %{
        component: "some_service",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        metrics: %{
          uptime_seconds: get_uptime(),
          requests_per_second: get_rps()
        }
      }
    end

    defp perform_health_check, do: :ok
    defp get_uptime, do: 123
    defp get_rps, do: 4.5
  end
  ```
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
