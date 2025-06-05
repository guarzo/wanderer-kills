defmodule WandererKills.Http.Retry do
  @moduledoc """
  Provides retry functionality with exponential backoff for HTTP requests.

  This module consolidates retry logic from across the application into a single,
  reusable implementation. It handles:
  - Exponential backoff with configurable parameters
  - Retryable error detection
  - Logging of retry attempts
  - Custom error types for different failure scenarios
  """

  require Logger
  alias WandererKills.Config
  alias WandererKills.Http.Errors.{ConnectionError, TimeoutError, RateLimitError}

  @type retry_opts :: [
          max_retries: non_neg_integer(),
          base_delay: non_neg_integer(),
          max_delay: non_neg_integer(),
          rescue_only: [module()]
        ]

  @doc """
  Retries a function with exponential backoff.

  ## Parameters
    - `fun` - A zero-arity function that either returns a value or raises one of the specified errors
    - `opts` - Retry options:
      - `:max_retries` - Maximum number of retry attempts (default: 3)
      - `:base_delay` - Initial delay in milliseconds (default: 1000)
      - `:max_delay` - Maximum delay in milliseconds (default: 30000)
      - `:rescue_only` - List of exception types to retry on
                         (default: `[ConnectionError, TimeoutError, RateLimitError]`)

  ## Returns
    - `{:ok, result}` on successful execution
    - `{:error, :max_retries_exceeded}` when max retries are reached
  """
  @spec retry_with_backoff((-> term()), retry_opts()) :: {:ok, term()} | {:error, term()}
  def retry_with_backoff(fun, opts \\ []) do
    retry_config = Config.retry()
    http_config = Map.get(retry_config, :http, %{})

    max_retries = Keyword.get(opts, :max_retries, Map.get(http_config, :max_retries, 3))
    base_delay = Keyword.get(opts, :base_delay, Map.get(http_config, :base_delay, 1000))
    max_delay = Keyword.get(opts, :max_delay, Map.get(http_config, :max_delay, 30000))

    rescue_only =
      Keyword.get(opts, :rescue_only, [
        ConnectionError,
        TimeoutError,
        RateLimitError
      ])

    # Create an Erlang backoff state: init(StartDelay, MaxDelay)
    backoff_state = :backoff.init(base_delay, max_delay)

    do_retry(fun, max_retries, backoff_state, rescue_only)
  end

  @spec do_retry((-> term()), non_neg_integer(), :backoff.backoff(), [module()]) ::
          {:ok, term()} | {:error, term()}
  defp do_retry(_fun, 0, _backoff_state, _rescue_only) do
    {:error, :max_retries_exceeded}
  end

  defp do_retry(fun, retries_left, backoff_state, rescue_only) do
    try do
      result = fun.()
      {:ok, result}
    rescue
      error ->
        if error.__struct__ in rescue_only do
          # Each time we fail, we call :backoff.fail/1 → {delay_ms, next_backoff}
          {delay_ms, next_backoff} = :backoff.fail(backoff_state)

          Logger.warning(
            "Retryable error: #{inspect(error)}. " <>
              "Retrying in #{delay_ms}ms (#{retries_left - 1} attempts left)."
          )

          Process.sleep(delay_ms)
          do_retry(fun, retries_left - 1, next_backoff, rescue_only)
        else
          # Not one of our listed retriable errors: bubble up immediately
          reraise(error, __STACKTRACE__)
        end
    end
  end

  @doc """
  Determines if an error is retriable.

  ## Parameters
    - `reason` - Error reason to check

  ## Returns
    - `true` - If error should be retried
    - `false` - If error should not be retried
  """
  @spec retriable_error?(term()) :: boolean()
  def retriable_error?(:rate_limited), do: true
  def retriable_error?(%RateLimitError{}), do: true
  def retriable_error?(%TimeoutError{}), do: true
  def retriable_error?(%ConnectionError{}), do: true
  def retriable_error?(_), do: false
end
