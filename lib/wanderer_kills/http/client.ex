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
  alias WandererKills.Support.{Error, Retry}
  alias WandererKills.Http.ClientProvider
  alias WandererKills.Observability.Telemetry
  alias WandererKills.Config

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

    case do_get(url, merged_headers, raw, into) do
      {:ok, response} ->
        {:ok, response}

      {:error, %Error{type: :timeout}} ->
        {:error, Error.http_error(:timeout, "Request to #{url} timed out", true)}

      {:error, %Error{type: :connection_failed}} ->
        {:error, Error.http_error(:connection_failed, "Connection failed for #{url}", true)}

      {:error, :rate_limited} ->
        {:error, Error.http_error(:rate_limited, "Rate limit exceeded for #{url}", true)}

      {:error, reason} ->
        {:error, Error.http_error(:request_failed, "Request failed: #{inspect(reason)}", false)}
    end
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
          {:error, Error.http_error(:timeout, "Request to #{url} timed out", true)}

        {:error, %{reason: :econnrefused}} ->
          {:error, Error.http_error(:connection_failed, "Connection refused for #{url}", true)}

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
          {:error, Error.http_error(:timeout, "Request to #{url} timed out", true)}

        {:error, %{reason: :econnrefused}} ->
          {:error, Error.http_error(:connection_failed, "Connection refused for #{url}", true)}

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
    case map_status_code(status) do
      :ok -> {:ok, resp}
      error -> error
    end
  end

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
    case map_status_code(status) do
      :ok -> parse_json(body)
      error -> error
    end
  end

  @doc """
  Retry an operation with specific service configuration.
  """
  @spec retry_operation((-> term()), atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def retry_operation(fun, service, opts \\ []) do
    retry_opts = retry_options(service, Keyword.get(opts, :retry_options, []))
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
  # Status Code and Error Handling (from Base module)
  # ============================================================================

  @type status_code :: integer()
  @type response_body :: map() | list() | binary()
  @type parsed_response :: {:ok, term()} | {:error, term()}

  # Success range
  @success_range 200..299

  # Common HTTP status codes
  @not_found 404
  @rate_limited 429
  @client_error_range 400..499
  @server_error_range 500..599

  # Maps HTTP status codes to standardized error responses
  @spec map_status_code(status_code()) :: :ok | {:error, term()}
  defp map_status_code(status) when status in @success_range, do: :ok
  defp map_status_code(@not_found), do: {:error, :not_found}
  defp map_status_code(@rate_limited), do: {:error, :rate_limited}

  defp map_status_code(status) when status in @server_error_range,
    do: {:error, {:server_error, status}}

  defp map_status_code(status) when status in @client_error_range,
    do: {:error, {:client_error, status}}

  defp map_status_code(status), do: {:error, {:http_error, status}}

  # Determines if an HTTP error is retryable
  @spec retriable_error?(term()) :: boolean()
  def retriable_error?({:error, :rate_limited}), do: true
  def retriable_error?({:error, {:server_error, _}}), do: true
  def retriable_error?({:error, {:client_error, _}}), do: false
  def retriable_error?({:error, :not_found}), do: false
  def retriable_error?(_), do: false

  # Configures retry options for a service
  @spec retry_options(atom(), keyword()) :: keyword()
  defp retry_options(service, opts) do
    config = Config.retry()

    base_options = [
      max_retries: config.http_max_retries,
      base_delay: config.http_base_delay,
      max_delay: config.http_max_delay,
      retry?: &retriable_error?/1
    ]

    # Use default retry counts for services
    service_options =
      case service do
        :esi -> [max_retries: 3]
        :zkb -> [max_retries: 5]
        _ -> []
      end

    base_options
    |> Keyword.merge(service_options)
    |> Keyword.merge(opts)
  end

  # Standard JSON parsing with error handling
  @spec parse_json(response_body()) :: {:ok, term()} | {:error, term()}
  defp parse_json(body) when is_map(body) or is_list(body), do: {:ok, body}

  defp parse_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, reason} ->
        {:error, Error.parsing_error(:invalid_json, "Invalid JSON response", %{reason: reason})}
    end
  end

  defp parse_json(_),
    do:
      {:error,
       Error.parsing_error(:invalid_response_type, "Response body must be string, map, or list")}

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
