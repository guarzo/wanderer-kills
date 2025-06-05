defmodule WandererKills.Core.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for external API calls to prevent cascade failures.

  Features:
  - Failure threshold detection
  - Automatic recovery after cooldown period
  - Half-open state for testing recovery
  - Per-service circuit breaking
  """

  use GenServer
  require Logger

  # Client API

  @doc """
  Starts the circuit breaker for a specific service.

  ## Parameters
  - `service` - The service name to monitor (e.g. :esi, :zkb)
  - `opts` - Configuration options:
    - `failure_threshold` - Number of failures before opening circuit (default: 5)
    - `cooldown_period` - Time in ms to wait before attempting recovery (default: 30_000)
    - `half_open_timeout` - Time in ms to wait in half-open state (default: 5_000)
  """
  def start_link(service, opts \\ []) do
    GenServer.start_link(__MODULE__, {service, opts}, name: via_tuple(service))
  end

  @doc """
  Executes a function with circuit breaker protection.

  ## Parameters
  - `service` - The service name to use circuit breaker for
  - `fun` - The function to execute

  ## Returns
  - `{:ok, result}` - On successful execution
  - `{:error, :circuit_open}` - When circuit is open
  - `{:error, reason}` - On execution failure
  """
  def execute(service, fun) do
    GenServer.call(via_tuple(service), {:execute, fun})
  end

  @doc """
  Manually forces the circuit breaker to open.

  ## Parameters
  - `service` - The service name to force open
  """
  def force_open(service) do
    GenServer.call(via_tuple(service), :force_open)
  end

  @doc """
  Manually forces the circuit breaker to close.

  ## Parameters
  - `service` - The service name to force close
  """
  def force_close(service) do
    GenServer.call(via_tuple(service), :force_close)
  end

  # Server Callbacks

  @impl true
  def init({service, opts}) do
    state = %{
      service: service,
      state: :closed,
      failure_count: 0,
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      cooldown_period: Keyword.get(opts, :cooldown_period, 30_000),
      half_open_timeout: Keyword.get(opts, :half_open_timeout, 5_000),
      last_failure_time: nil,
      half_open_timer: nil
    }

    Logger.info("Started circuit breaker for service", %{
      service: service,
      state: state.state,
      failure_threshold: state.failure_threshold,
      cooldown_period: state.cooldown_period
    })

    {:ok, state}
  end

  @impl true
  def handle_call({:execute, _fun}, _from, %{state: :open} = state) do
    Logger.warning("Circuit breaker is open, rejecting request", %{
      service: state.service,
      state: state.state,
      last_failure_time: state.last_failure_time
    })

    {:reply, {:error, :circuit_open}, state}
  end

  def handle_call({:execute, fun}, _from, %{state: :half_open} = state) do
    case execute_with_timeout(fun, state.half_open_timeout) do
      {:ok, result} ->
        Logger.info("Circuit breaker recovered, closing circuit", %{
          service: state.service,
          state: :closed
        })

        {:reply, {:ok, result}, %{state | state: :closed, failure_count: 0}}

      {:error, reason} ->
        Logger.warning("Circuit breaker recovery failed, reopening circuit", %{
          service: state.service,
          state: :open,
          error: reason
        })

        {:reply, {:error, reason},
         %{state | state: :open, last_failure_time: System.monotonic_time()}}
    end
  end

  def handle_call({:execute, fun}, _from, %{state: :closed} = state) do
    case execute_with_timeout(fun, state.cooldown_period) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}

      {:error, reason} ->
        new_failure_count = state.failure_count + 1

        new_state = %{
          state
          | failure_count: new_failure_count,
            last_failure_time: System.monotonic_time()
        }

        if new_failure_count >= state.failure_threshold do
          Logger.warning("Circuit breaker threshold reached, opening circuit", %{
            service: state.service,
            state: :open,
            failure_count: new_failure_count,
            failure_threshold: state.failure_threshold
          })

          schedule_half_open(state.cooldown_period)
          {:reply, {:error, reason}, %{new_state | state: :open}}
        else
          Logger.warning("Circuit breaker failure count increased", %{
            service: state.service,
            failure_count: new_failure_count,
            failure_threshold: state.failure_threshold
          })

          {:reply, {:error, reason}, new_state}
        end
    end
  end

  def handle_call(:force_open, _from, state) do
    Logger.warning("Circuit breaker manually forced open", %{
      service: state.service,
      state: :open
    })

    {:reply, :ok, %{state | state: :open, last_failure_time: System.monotonic_time()}}
  end

  def handle_call(:force_close, _from, state) do
    Logger.info("Circuit breaker manually forced closed", %{
      service: state.service,
      state: :closed
    })

    {:reply, :ok, %{state | state: :closed, failure_count: 0}}
  end

  @impl true
  def handle_info(:half_open_timeout, state) do
    Logger.info("Circuit breaker entering half-open state", %{
      service: state.service,
      state: :half_open
    })

    {:noreply, %{state | state: :half_open, half_open_timer: nil}}
  end

  # Private Functions

  defp via_tuple(service) do
    {:via, Registry, {WandererKills.Registry, {__MODULE__, service}}}
  end

  defp execute_with_timeout(fun, timeout) do
    task = Task.async(fun)

    case Task.await(task, timeout) do
      {:ok, result} -> {:ok, result}
      {:exit, reason} -> {:error, reason}
    end
  end

  defp schedule_half_open(cooldown_period) do
    Process.send_after(self(), :half_open_timeout, cooldown_period)
  end
end
