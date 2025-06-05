defmodule WandererKills.Infrastructure.HealthChecks.HealthCheckBehaviour do
  @moduledoc """
  Behaviour for implementing health check modules.

  This behaviour standardizes how health checks are implemented across
  different subsystems in the application.
  """

  @type health_status :: :healthy | :unhealthy | :degraded
  @type check_result :: %{
          status: health_status(),
          component: String.t(),
          details: map(),
          timestamp: DateTime.t(),
          duration_ms: non_neg_integer()
        }

  @doc """
  Performs a health check and returns the result.

  Should return a map with:
  - `:status` - :healthy, :unhealthy, or :degraded
  - `:component` - String identifying the component being checked
  - `:details` - Map with additional information about the check
  - `:timestamp` - When the check was performed
  - `:duration_ms` - How long the check took
  """
  @callback check() :: check_result()

  @doc """
  Returns the name of the component being checked.
  """
  @callback component_name() :: String.t()

  @doc """
  Returns the timeout for this health check in milliseconds.
  Defaults to 5000ms if not implemented.
  """
  @callback timeout_ms() :: non_neg_integer()

  @optional_callbacks timeout_ms: 0

  @doc """
  Default implementation of timeout_ms/0.
  """
  def default_timeout_ms, do: 5_000

  @doc """
  Helper function to execute a health check with timing and error handling.
  """
  def execute_check(module) when is_atom(module) do
    start_time = System.monotonic_time(:millisecond)
    timeout = if function_exported?(module, :timeout_ms, 0), do: module.timeout_ms(), else: default_timeout_ms()

    try do
      task = Task.async(fn -> module.check() end)

      case Task.await(task, timeout) do
        %{status: _, component: _, details: _} = result ->
          duration = System.monotonic_time(:millisecond) - start_time
          Map.merge(result, %{
            timestamp: DateTime.utc_now(),
            duration_ms: duration
          })

        invalid_result ->
          %{
            status: :unhealthy,
            component: module.component_name(),
            details: %{error: "Invalid health check result format", result: invalid_result},
            timestamp: DateTime.utc_now(),
            duration_ms: System.monotonic_time(:millisecond) - start_time
          }
      end
    catch
      :exit, {:timeout, _} ->
        %{
          status: :unhealthy,
          component: module.component_name(),
          details: %{error: "Health check timed out", timeout_ms: timeout},
          timestamp: DateTime.utc_now(),
          duration_ms: timeout
        }

      kind, reason ->
        %{
          status: :unhealthy,
          component: module.component_name(),
          details: %{error: "Health check failed", kind: kind, reason: inspect(reason)},
          timestamp: DateTime.utc_now(),
          duration_ms: System.monotonic_time(:millisecond) - start_time
        }
    end
  end
end
