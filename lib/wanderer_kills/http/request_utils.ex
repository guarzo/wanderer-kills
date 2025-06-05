defmodule WandererKills.Http.RequestUtils do
  @moduledoc """
  Utility functions for HTTP request handling.

  This module consolidates HTTP retry logic, error handling, and telemetry
  that was duplicated across HTTP client modules.
  """

  require Logger
  alias WandererKills.Http.Errors.{ConnectionError, TimeoutError}
  alias WandererKills.Observability.Telemetry

  @type url :: String.t()
  @type method :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Wraps an HTTP request with telemetry and standardized error handling.

  ## Parameters
  - `method` - HTTP method (e.g., "GET", "POST")
  - `url` - Request URL
  - `request_fn` - Function that performs the actual HTTP request

  ## Returns
  - `{:ok, response}` - On success
  - `{:error, reason}` - On failure with standardized error types
  """
  @spec wrap_request(method(), url(), (-> term())) :: response()
  def wrap_request(method, url, request_fn) when is_function(request_fn, 0) do
    start_time = System.monotonic_time()

    Telemetry.http_request_start(method, url)

    result =
      try do
        request_fn.()
      rescue
        error ->
          standardize_error(error, url)
      catch
        thrown_value ->
          standardize_error(thrown_value, url)
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, %{status: status}} ->
        Telemetry.http_request_stop(method, url, duration, status)

      {:error, reason} ->
        Telemetry.http_request_error(method, url, duration, reason)
    end

    result
  end

  @doc """
  Standardizes HTTP errors into consistent error types.

  ## Parameters
  - `error` - The error to standardize
  - `url` - The URL that was being requested (for context)

  ## Returns
  - Standardized error tuple
  """
  @spec standardize_error(term(), url()) :: {:error, term()}
  def standardize_error(%{reason: :timeout}, url) do
    {:error, %TimeoutError{message: "Request to #{url} timed out"}}
  end

  def standardize_error(%{reason: :econnrefused}, url) do
    {:error, %ConnectionError{message: "Connection refused for #{url}"}}
  end

  def standardize_error(%{reason: :nxdomain}, url) do
    {:error, %ConnectionError{message: "Domain not found for #{url}"}}
  end

  def standardize_error(%{reason: :closed}, url) do
    {:error, %ConnectionError{message: "Connection closed for #{url}"}}
  end

  def standardize_error(:timeout, url) do
    {:error, %TimeoutError{message: "Request to #{url} timed out"}}
  end

  def standardize_error(:econnrefused, url) do
    {:error, %ConnectionError{message: "Connection refused for #{url}"}}
  end

  def standardize_error(error, _url) do
    {:error, error}
  end

  @doc """
  Logs retry attempts with consistent formatting.

  ## Parameters
  - `attempt` - Current attempt number
  - `max_attempts` - Maximum number of attempts
  - `error` - The error that caused the retry
  - `delay` - Delay before next attempt in milliseconds
  - `url` - URL being requested
  """
  @spec log_retry(pos_integer(), pos_integer(), term(), pos_integer(), url()) :: :ok
  def log_retry(attempt, max_attempts, error, delay, url) do
    Logger.warning(
      "HTTP request failed, retrying in #{delay}ms",
      attempt: attempt,
      max_attempts: max_attempts,
      remaining_attempts: max_attempts - attempt,
      error: inspect(error),
      url: url,
      delay_ms: delay
    )
  end

  @doc """
  Determines if an HTTP response status is retryable.

  ## Parameters
  - `status` - HTTP status code

  ## Returns
  - `true` if the status should be retried
  - `false` otherwise
  """
  @spec retryable_status?(integer()) :: boolean()
  def retryable_status?(status) when status in [429, 500, 502, 503, 504], do: true
  def retryable_status?(_status), do: false

  @doc """
  Merges default headers with custom headers, ensuring defaults are not overridden.

  ## Parameters
  - `default_headers` - Default headers to include
  - `custom_headers` - Custom headers from user

  ## Returns
  - Merged headers list with defaults taking precedence for conflicts
  """
  @spec merge_headers(headers(), headers()) :: headers()
  def merge_headers(default_headers, custom_headers) do
    # Convert to maps for easier merging, then back to list
    default_map = Map.new(default_headers, fn {k, v} -> {String.downcase(k), {k, v}} end)
    custom_map = Map.new(custom_headers, fn {k, v} -> {String.downcase(k), {k, v}} end)

    Map.merge(custom_map, default_map)
    |> Map.values()
  end
end
