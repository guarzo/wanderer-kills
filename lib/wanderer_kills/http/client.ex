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

  The module defines several custom error types (in `WandererKills.Support.Error`):
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

  require Logger
  import WandererKills.Support.Logger
  alias WandererKills.Support.Error.{ConnectionError, TimeoutError, RateLimitError}
  alias WandererKills.Support.{Error, Retry}
  alias WandererKills.Http.{ClientProvider, Base}
  alias WandererKills.Observability.Telemetry

  @type url :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type opts :: keyword()
  @type response :: {:ok, map()} | {:error, term()}

  # Get the configured HTTP client implementation
  defp http_client do
    WandererKills.Config.app().http_client
  end

  # Real HTTP implementation using Req
  def real_get(url, headers, raw, into) do
    Req.get(url, headers: headers, raw: raw, into: into)
  end

  # Implementation callbacks (not part of behaviour)

  # ============================================================================
  # HttpClient Behaviour Implementation
  # ============================================================================

  @doc """
  Makes a GET request.

  This is a simplified version that delegates to get_with_rate_limit/2.
  """
  @spec get(url(), headers(), opts()) :: response()
  def get(url, headers \\ [], options \\ []) do
    opts = Keyword.merge(options, headers: headers)
    get_with_rate_limit(url, opts)
  end

  @doc """
  Makes a POST request with JSON payload.

  ## Parameters
  - `url` - The URL to post to
  - `body` - The JSON payload (will be encoded automatically)
  - `options` - Request options (headers, timeout, etc.)

  ## Returns
  - `{:ok, response}` - On success
  - `{:error, reason}` - On failure
  """
  @spec post(url(), map(), opts()) :: response()
  def post(url, body, options \\ []) do
    default_headers = [{"content-type", "application/json"}]
    headers = Keyword.get(options, :headers, []) ++ default_headers
    opts = Keyword.put(options, :headers, headers)

    Retry.retry_with_backoff(
      fn ->
        do_post(url, body, opts)
      end,
      operation_name: "HTTP POST #{url}"
    )
  end

  # ============================================================================
  # Main Implementation
  # ============================================================================

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
    # Check if we should use a mock client
    case http_client() do
      __MODULE__ ->
        # Use the real implementation
        do_get_with_rate_limit(url, opts)

      mock_client ->
        # Use mock implementation directly
        mock_client.get_with_rate_limit(url, opts)
    end
  end

  # The real implementation moved to a private function
  defp do_get_with_rate_limit(url, opts) do
    headers = Keyword.get(opts, :headers, [])
    raw = Keyword.get(opts, :raw, false)
    into = Keyword.get(opts, :into)

    # Merge default headers with custom headers
    merged_headers = ClientProvider.default_headers() ++ headers

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
      case real_get(url, headers, raw, into) do
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

  @spec do_post(url(), map(), opts()) :: {:ok, term()} | {:error, term()}
  defp do_post(url, body, opts) do
    start_time = System.monotonic_time()

    Telemetry.http_request_start("POST", url)

    headers = Keyword.get(opts, :headers, [])
    timeout = Keyword.get(opts, :timeout, 10_000)

    result =
      case Req.post(url, json: body, headers: headers, receive_timeout: timeout) do
        {:ok, %Req.Response{status: status, body: body}} ->
          handle_status_code(status, %{status: status, body: body})

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
        Telemetry.http_request_stop("POST", url, duration, status)

      {:error, reason} ->
        Telemetry.http_request_error("POST", url, duration, reason)
    end

    result
  end

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
    case Base.map_status_code(status) do
      :ok -> {:ok, resp}
      error -> error
    end
  end

  @spec retriable_error?(term()) :: boolean()
  def retriable_error?(error), do: Base.retryable_error?(error)

  # ============================================================================
  # Consolidated Utility Functions (from Http.Util)
  # ============================================================================

  @doc """
  Standard request with telemetry and error handling.

  Provides consistent request patterns with automatic telemetry,
  logging, and error handling across all HTTP clients.
  """
  @spec request_with_telemetry(url(), atom(), keyword()) :: response()
  def request_with_telemetry(url, service, opts \\ []) do
    operation = Keyword.get(opts, :operation, :http_request)
    request_opts = ClientProvider.build_request_opts(opts)

    log_debug("Starting HTTP request",
      url: url,
      service: service,
      operation: operation
    )

    case get_with_rate_limit(url, request_opts) do
      {:ok, response} ->
        log_debug("HTTP request successful",
          url: url,
          service: service,
          operation: operation,
          status: Map.get(response, :status)
        )

        {:ok, response}

      {:error, reason} ->
        log_error("HTTP request failed",
          url: url,
          service: service,
          operation: operation,
          error: reason
        )

        {:error, reason}
    end
  end

  @doc """
  Parse JSON response with error handling.

  Provides consistent JSON parsing across all HTTP clients.
  """
  @spec parse_json_response(map()) :: {:ok, term()} | {:error, term()}
  def parse_json_response(%{status: status, body: body}) do
    case Base.map_status_code(status) do
      :ok -> Base.parse_json(body)
      error -> error
    end
  end

  @doc """
  Retry an operation with specific service configuration.
  """
  @spec retry_operation((-> term()), atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def retry_operation(fun, service, opts \\ []) do
    retry_opts = Base.retry_options(service, opts)
    operation_name = Keyword.get(opts, :operation_name, "#{service} request")

    Retry.retry_http_operation(fun, Keyword.put(retry_opts, :operation_name, operation_name))
  end

  @doc """
  Validate response format and structure.

  Provides consistent validation across different API responses.
  """
  @spec validate_response_structure(term(), list()) :: {:ok, term()} | {:error, term()}
  def validate_response_structure(data, required_fields) when is_map(data) do
    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(data, &1))

    case missing_fields do
      [] ->
        {:ok, data}

      missing ->
        {:error,
         Error.validation_error(:missing_fields, "Missing required fields", %{missing: missing})}
    end
  end

  def validate_response_structure(data, _required_fields) when is_list(data) do
    {:ok, data}
  end

  def validate_response_structure(data, _required_fields) do
    {:error,
     Error.validation_error(:invalid_format, "Invalid response format", %{type: typeof(data)})}
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp typeof(data) when is_map(data), do: :map
  defp typeof(data) when is_list(data), do: :list
  defp typeof(data) when is_binary(data), do: :string
  defp typeof(data) when is_integer(data), do: :integer
  defp typeof(data) when is_float(data), do: :float
  defp typeof(data) when is_boolean(data), do: :boolean
  defp typeof(data) when is_atom(data), do: :atom
  defp typeof(_), do: :unknown
end
