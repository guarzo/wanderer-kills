defmodule WandererKills.Http.Client do
  @moduledoc """
  Core HTTP client that handles rate limiting, retries, and common HTTP functionality.

  This module provides a robust HTTP client implementation that handles:
    - Rate limiting and backoff
    - Automatic retries with exponential backoff
    - JSON response parsing
    - Error handling and logging
    - Custom error types for different failure scenarios
    - Telemetry for monitoring HTTP calls

  ## Usage

      # Basic GET request with rate limiting
      {:ok, response} = WandererKills.Http.Client.get_with_rate_limit("https://api.example.com/data")

      # GET request with custom options
      opts = [
        params: [query: "value"],
        headers: [{"authorization", "Bearer token"}],
        timeout: 5000
      ]
      {:ok, response} = WandererKills.Http.Client.get_with_rate_limit("https://api.example.com/data", opts)

  ## Error Handling

  The module defines several custom error types (in `WandererKills.Http.Errors`):
    - `ConnectionError` - Raised when a connection fails
    - `TimeoutError` - Raised when a request times out
    - `RateLimitError` - Raised when rate limit is exceeded

  All functions return either `{:ok, result}` or `{:error, reason}` tuples.

  ## Telemetry

  The module emits the following telemetry events:

  - `[:wanderer_kills, :http, :request, :start]` - When a request starts
    - Metadata: `%{method: "GET", url: url}`
  - `[:wanderer_kills, :http, :request, :stop]` - When a request completes
    - Metadata: `%{method: "GET", url: url, status_code: status}` on success
    - Metadata: `%{method: "GET", url: url, error: reason}` on failure
  """

  @behaviour WandererKills.Http.ClientBehaviour

  require Logger
  alias WandererKills.Http.Errors.{ConnectionError, TimeoutError, RateLimitError}
  alias WandererKills.Retry
  alias WandererKills.Infrastructure.Telemetry

  @user_agent "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"

  @type url :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type opts :: keyword()
  @type response :: {:ok, map()} | {:error, term()}

  @callback get(url :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_with_rate_limit(url :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @impl true
  @doc """
  Makes a GET request with rate limiting and retries.

  ## Options
    - `:params` - Query parameters (default: [])
    - `:headers` - HTTP headers (default: [])
    - `:timeout` - Request timeout in milliseconds (default: 30_000)
    - `:recv_timeout` - Receive timeout in milliseconds (default: 60_000)
    - `:raw` - If true, returns raw response body without JSON parsing (default: false)
    - `:into` - Optional module to decode the response into (default: nil)
    - `:retries` - Number of retry attempts (default: 3)

  ## Returns
    - `{:ok, response}` - On success, response is either a map (parsed JSON) or raw body
    - `{:error, reason}` - On failure, reason can be:
      - `:not_found` - HTTP 404
      - `:rate_limited` - HTTP 429 (after exhausting retries)
      - `"HTTP status"` - Other HTTP errors
      - Other error terms for network/parsing failures

  ## Examples

  ```elixir
  # Basic request
  {:ok, response} = get_with_rate_limit("https://api.example.com/data")

  # With options
  {:ok, response} = get_with_rate_limit("https://api.example.com/data",
    params: [query: "value"],
    headers: [{"authorization", "Bearer token"}],
    timeout: 5_000
  )
  ```
  """
  @spec get_with_rate_limit(url(), opts()) :: response()
  def get_with_rate_limit(url, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    raw = Keyword.get(opts, :raw, false)
    into = Keyword.get(opts, :into)

    # Merge default user-agent into headers
    merged_headers = [{"user-agent", @user_agent} | headers]

    fetch_fun = fn ->
      case do_get(url, merged_headers, raw, into) do
        {:ok, response} ->
          response

        {:error, :rate_limited} ->
          # Turn a 429 into a retryable exception
          raise RateLimitError, message: "HTTP 429 Rate Limit for #{url}"

        {:error, %TimeoutError{} = err} ->
          raise err

        {:error, %ConnectionError{} = err} ->
          raise err

        {:error, other_reason} ->
          # Non-retriable: short-circuit
          throw({:error, other_reason})
      end
    end

    result =
      try do
        {:ok, response} = Retry.retry_with_backoff(fetch_fun)
        {:ok, response}
      catch
        {:error, reason} ->
          {:error, reason}
      end

    result
  end

  @spec do_get(url(), headers(), boolean(), module() | nil) :: {:ok, term()} | {:error, term()}
  defp do_get(url, headers, raw, into) do
    start_time = System.monotonic_time()

    Telemetry.http_request_start("GET", url)

    result =
      case Req.get(url, headers: headers, raw: raw, into: into) do
        {:ok, %{status: status} = resp} ->
          handle_status_code(status, resp)

        {:error, %{reason: :timeout}} ->
          {:error, %TimeoutError{message: "Request to #{url} timed out"}}

        {:error, %{reason: :econnrefused}} ->
          {:error, %ConnectionError{message: "Connection refused for #{url}"}}

        {:error, reason} ->
          {:error, reason}
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, %{status: status}} ->
        Telemetry.http_request_stop("GET", url, duration, status)

      {:error, reason} ->
        Telemetry.http_request_error("GET", url, duration, reason)
    end

    result
  end

  @impl true
  @doc """
  Centralized HTTP status code handling.

  This function provides unified status code handling for all HTTP clients
  in the application, using configuration-driven status code mappings.

  ## Parameters
  - `status` - HTTP status code
  - `response` - HTTP response map (optional, defaults to empty map)

  ## Returns
  - `{:ok, response}` - For successful status codes (200-299)
  - `{:error, :not_found}` - For 404 status
  - `{:error, :rate_limited}` - For 429 status
  - `{:error, "HTTP {status}"}` - For other error status codes

  ## Examples

  ```elixir
  # Success case
  {:ok, response} = handle_status_code(200, %{body: "data"})

  # Not found
  {:error, :not_found} = handle_status_code(404)

  # Rate limited
  {:error, :rate_limited} = handle_status_code(429)

  # Other errors
  {:error, "HTTP 500"} = handle_status_code(500)
  ```
  """
  @spec handle_status_code(integer(), map()) :: {:ok, map()} | {:error, term()}
  def handle_status_code(status, resp \\ %{}) do
    status_codes = get_config(:http_status_codes)

    cond do
      status in status_codes.success ->
        {:ok, resp}

      status == status_codes.not_found ->
        {:error, :not_found}

      status == status_codes.rate_limited ->
        {:error, :rate_limited}

      status in status_codes.retryable ->
        {:error, "HTTP #{status}"}

      status in status_codes.fatal ->
        {:error, "HTTP #{status}"}

      true ->
        {:error, "HTTP #{status}"}
    end
  end

  @spec retriable_error?(term()) :: boolean()
  def retriable_error?(error), do: Retry.retriable_http_error?(error)

  # Helper function to get configuration values
  defp get_config(key) do
    Application.get_env(:wanderer_kills, key)
  end
end
