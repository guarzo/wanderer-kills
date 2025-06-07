defmodule WandererKills.Core do
  @moduledoc """
  Public API for the WandererKills Core domain.

  This module provides a unified interface to core utilities including:
  - Batch processing operations
  - Time utilities (Clock)
  - Circuit breaker functionality
  - Configuration access
  - Constants

  ## Usage

  ```elixir
  # Instead of: alias WandererKills.Core.BatchProcessor
  alias WandererKills.Core

  {:ok, results} = Core.process_batch(items, &process_item/1)
  ```

  This provides a stable interface for core utilities across the application.
  """

  # Core utilities
  alias WandererKills.Infrastructure.{BatchProcessor, Clock, CircuitBreaker, Config}
  alias WandererKills.Infrastructure.Constants

  #
  # Batch Processing API
  #

  @doc """
  Processes a list of items in parallel batches.
  """
  @spec process_batch([term()], (term() -> term()), keyword()) ::
          {:ok, [term()]} | {:partial, [term()], [term()]} | {:error, term()}
  def process_batch(items, processor_fn, opts \\ []) do
    BatchProcessor.process_parallel(items, processor_fn, opts)
  end

  @doc """
  Processes items sequentially with error handling.
  """
  @spec process_sequential([term()], (term() -> term()), keyword()) ::
          {:ok, [term()]} | {:partial, [term()], [term()]} | {:error, term()}
  def process_sequential(items, processor_fn, opts \\ []) do
    BatchProcessor.process_sequential(items, processor_fn, opts)
  end

  #
  # Time/Clock API
  #

  @doc """
  Gets the current time (mockable in tests).
  """
  @spec now() :: DateTime.t()
  def now do
    Clock.now()
  end

  @doc """
  Gets the current time as a Unix timestamp in milliseconds.
  """
  @spec unix_now() :: integer()
  def unix_now do
    Clock.now_milliseconds()
  end

  @doc """
  Gets the current time as an ISO8601 string.
  """
  @spec now_iso8601() :: String.t()
  def now_iso8601 do
    Clock.now_iso8601()
  end

  #
  # Circuit Breaker API
  #

  @doc """
  Executes a function with circuit breaker protection.
  """
  @spec execute_with_circuit_breaker(atom(), (-> term())) :: term()
  def execute_with_circuit_breaker(service, fun) do
    CircuitBreaker.execute(service, fun)
  end

  @doc """
  Forces a circuit breaker to open state.
  """
  @spec force_circuit_open(atom()) :: :ok
  def force_circuit_open(service) do
    CircuitBreaker.force_open(service)
  end

  @doc """
  Forces a circuit breaker to close state.
  """
  @spec force_circuit_close(atom()) :: :ok
  def force_circuit_close(service) do
    CircuitBreaker.force_close(service)
  end

  #
  # Configuration API
  #

  @doc """
  Gets cache TTL for a specific cache type.
  """
  @spec cache_config(atom()) :: map()
  def cache_config(cache_type) do
    %{ttl: Config.cache_ttl(cache_type)}
  end

  @doc """
  Gets HTTP configuration.
  """
  @spec http_config() :: map()
  def http_config do
    %{
      max_retries: Config.retry_http_max_retries(),
      base_delay: Config.retry_http_base_delay(),
      max_delay: Config.retry_http_max_delay()
    }
  end

  @doc """
  Gets retry configuration for HTTP.
  """
  @spec retry_config() :: map()
  def retry_config do
    http_config()
  end

  #
  # Constants API
  #

  @doc """
  Gets the default cache TTL for killmails.
  """
  @spec default_cache_ttl() :: integer()
  def default_cache_ttl do
    Config.cache_ttl(:killmails)
  end

  @doc """
  Gets the default batch size for operations.
  """
  @spec default_batch_size() :: integer()
  def default_batch_size do
    Constants.concurrency(:batch_size)
  end

  #
  # Type Definitions
  #

  @type processor_fn(t) :: (t -> term())
  @type batch_result(t) :: {:ok, [t]} | {:partial, [t], [t]} | {:error, term()}
  @type service_name :: atom()
end
