defmodule WandererKills.Support.Retry do
  @moduledoc """
  Provides retry functionality with exponential backoff for any operation.

  This module consolidates retry logic from across the application into a single,
  reusable implementation. It handles:
  - Exponential backoff with configurable parameters
  - Retryable error detection
  - Logging of retry attempts
  - Custom error types for different failure scenarios

  Originally designed for HTTP requests but generalized to handle any retryable operation.
  """

  require Logger
  alias WandererKills.Config

  # Retry Configuration Constants
  @default_base_delay 1_000
  @max_backoff_delay 60_000
  @backoff_factor 2

  @doc "Default base delay for retry operations"
  @spec default_base_delay() :: non_neg_integer()
  def default_base_delay, do: @default_base_delay

  @doc "Maximum backoff delay for retry operations"
  @spec max_backoff_delay() :: non_neg_integer()
  def max_backoff_delay, do: @max_backoff_delay

  @doc "Backoff factor for exponential backoff"
  @spec backoff_factor() :: number()
  def backoff_factor, do: @backoff_factor

  @type retry_opts :: [
          max_retries: non_neg_integer(),
          base_delay: non_neg_integer(),
          max_delay: non_neg_integer(),
          rescue_only: [module()],
          operation_name: String.t()
        ]

  @doc """
  Retries a function with exponential backoff.

  ## Parameters
    - `fun` - A zero-arity function that either returns a value or raises one of the specified errors
    - `opts` - Retry options:
      - `:max_retries` - Maximum number of retry attempts (default: 3)
      - `:base_delay` - Initial delay in milliseconds (default: 1000)
      - `:max_delay` - Maximum delay in milliseconds (default: 30000)
      - `:rescue_only` - List of exception types to retry on (default: all common retryable errors)
      - `:operation_name` - Name for logging purposes (default: "operation")

  ## Returns
    - `{:ok, result}` on successful execution
    - `{:error, :max_retries_exceeded}` when max retries are reached
  """
  @spec retry_with_backoff((-> term()), retry_opts()) :: {:ok, term()} | {:error, term()}
  def retry_with_backoff(fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, Config.retry().http_max_retries)
    base_delay = Keyword.get(opts, :base_delay, Config.retry().http_base_delay)
    max_delay = Keyword.get(opts, :max_delay, Config.retry().http_max_delay)
    operation_name = Keyword.get(opts, :operation_name, "operation")

    rescue_only =
      Keyword.get(opts, :rescue_only, [
        WandererKills.Support.Error.ConnectionError,
        WandererKills.Support.Error.TimeoutError,
        WandererKills.Support.Error.RateLimitError,
        # Add common retryable exceptions
        RuntimeError,
        ArgumentError
      ])

    # Create an Erlang backoff state: init(StartDelay, MaxDelay)
    backoff_state = :backoff.init(base_delay, max_delay)

    do_retry(fun, max_retries, backoff_state, rescue_only, operation_name)
  end

  @spec do_retry((-> term()), non_neg_integer(), :backoff.backoff(), [module()], String.t()) ::
          {:ok, term()} | {:error, term()}
  defp do_retry(_fun, 0, _backoff_state, _rescue_only, operation_name) do
    Logger.error("#{operation_name} failed after exhausting all retry attempts")
    {:error, :max_retries_exceeded}
  end

  defp do_retry(fun, retries_left, backoff_state, rescue_only, operation_name) do
    result = fun.()
    {:ok, result}
  rescue
    error ->
      if error.__struct__ in rescue_only do
        # Each time we fail, we call :backoff.fail/1 → {delay_ms, next_backoff}
        {delay_ms, next_backoff} = :backoff.fail(backoff_state)

        Logger.warning(
          "#{operation_name} failed with retryable error: #{inspect(error)}. " <>
            "Retrying in #{delay_ms}ms (#{retries_left - 1} attempts left)."
        )

        Process.sleep(delay_ms)
        do_retry(fun, retries_left - 1, next_backoff, rescue_only, operation_name)
      else
        # Not one of our listed retriable errors: bubble up immediately
        Logger.error("#{operation_name} failed with non-retryable error: #{inspect(error)}")
        reraise(error, __STACKTRACE__)
      end
  end

  @doc """
  Determines if an error is retriable for HTTP operations.

  ## Parameters
    - `reason` - Error reason to check

  ## Returns
    - `true` - If error should be retried
    - `false` - If error should not be retried
  """
  @spec retriable_http_error?(term()) :: boolean()
  def retriable_http_error?(:rate_limited), do: true
  def retriable_http_error?(%WandererKills.Support.Error.RateLimitError{}), do: true
  def retriable_http_error?(%WandererKills.Support.Error.TimeoutError{}), do: true
  def retriable_http_error?(%WandererKills.Support.Error.ConnectionError{}), do: true
  def retriable_http_error?(_), do: false

  @doc """
  Alias for retriable_http_error?/1 for backward compatibility.
  """
  @spec retriable_error?(term()) :: boolean()
  def retriable_error?(reason), do: retriable_http_error?(reason)

  @doc """
  Convenience function for retrying HTTP operations with sensible defaults.

  ## Parameters
    - `fun` - Function to retry
    - `opts` - Options (same as retry_with_backoff/2)

  ## Returns
    - `{:ok, result}` on success
    - `{:error, reason}` on failure
  """
  @spec retry_http_operation((-> term()), retry_opts()) :: {:ok, term()} | {:error, term()}
  def retry_http_operation(fun, opts \\ []) do
    default_opts = [
      operation_name: "HTTP request",
      rescue_only: [
        WandererKills.Support.Error.ConnectionError,
        WandererKills.Support.Error.TimeoutError,
        WandererKills.Support.Error.RateLimitError
      ]
    ]

    merged_opts = Keyword.merge(default_opts, opts)
    retry_with_backoff(fun, merged_opts)
  end
end
