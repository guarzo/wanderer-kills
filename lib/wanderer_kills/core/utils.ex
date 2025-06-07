defmodule WandererKills.Core.Http.Utils do
  @moduledoc """
  Consolidated HTTP utilities for WandererKills.

  This module merges functionality from:
  - `util.ex` - Basic request option building and response handling
  - `client_util.ex` - JSON fetching and parsing utilities
  - `request_utils.ex` - Request wrapping and error standardization

  ## Usage

  ```elixir
  # JSON fetching
  {:ok, data} = Utils.fetch_json("https://api.example.com/data")

  # Raw data fetching
  {:ok, binary} = Utils.fetch_raw("https://example.com/file.csv")

  # Request wrapping with telemetry
  result = Utils.wrap_request("GET", url, fn ->
    HttpClient.get(url)
  end)

  # Error handling
  standardized_error = Utils.standardize_error(error, url)
  ```
  """

  require Logger
  alias WandererKills.Core.Http.Client
  alias WandererKills.Core.Http.ClientProvider
  alias WandererKills.Infrastructure.Error
  alias WandererKills.Observability.Telemetry

  @type url :: String.t()
  @type method :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type opts :: keyword()
  @type response :: {:ok, map()} | {:error, term()}
  @type parser_function :: (binary() -> {:ok, term()} | {:error, term()})

  # Core request handling

  @doc """
  Makes an HTTP request with standardized error handling and telemetry.

  ## Parameters
  - `method` - HTTP method ("GET", "POST", etc.)
  - `url` - Request URL
  - `opts` - Request options (headers, params, timeout, etc.)

  ## Returns
  - `{:ok, response}` - On success
  - `{:error, error}` - On failure with standardized error

  ## Examples

  ```elixir
  {:ok, response} = Utils.make_request("GET", "https://api.example.com/data")
  {:ok, response} = Utils.make_request("POST", url, [
    body: Jason.encode!(data),
    headers: [{"content-type", "application/json"}]
  ])
  ```
  """
  @spec make_request(method(), url(), opts()) :: response()
  def make_request(method, url, opts \\ []) do
    request_opts = build_request_opts(opts)

    wrap_request(method, url, fn ->
      ClientProvider.get().get_with_rate_limit(url, request_opts)
    end)
  end

  @doc """
  Handles HTTP response and converts to standard format.

  ## Parameters
  - `response` - HTTP response
  - `client` - Optional client module (defaults to Client)

  ## Returns
  - `{:ok, data}` - On success
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, data} = Utils.handle_response(response)
  ```
  """
  @spec handle_response(Req.Response.t(), module()) :: response()
  def handle_response(response, client \\ Client) do
    case client.handle_status_code(response.status, response) do
      {:ok, _} -> {:ok, response.body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Standardizes HTTP errors into consistent error types.

  ## Parameters
  - `error` - The error to standardize
  - `url` - The URL that was being requested

  ## Returns
  - Standardized error using WandererKills.Infrastructure.Error

  ## Examples

  ```elixir
  standardized_error = Utils.standardize_error(error, url)
  ```
  """
  @spec standardize_error(term(), url()) :: Error.t()
  def standardize_error(%{reason: :timeout}, url) do
    Error.timeout_error("Request to #{url} timed out", %{url: url})
  end

  def standardize_error(%{reason: :econnrefused}, url) do
    Error.connection_error("Connection refused for #{url}", %{url: url})
  end

  def standardize_error(%{reason: :nxdomain}, url) do
    Error.connection_error("Domain not found for #{url}", %{url: url})
  end

  def standardize_error(%{reason: :closed}, url) do
    Error.connection_error("Connection closed for #{url}", %{url: url})
  end

  def standardize_error(:timeout, url) do
    Error.timeout_error("Request to #{url} timed out", %{url: url})
  end

  def standardize_error(:econnrefused, url) do
    Error.connection_error("Connection refused for #{url}", %{url: url})
  end

  def standardize_error(error, url) do
    Error.http_error(:unknown, "HTTP error: #{inspect(error)}", false, %{
      url: url,
      original_error: error
    })
  end

  # Convenience methods

  @doc """
  Fetches JSON data from a URL with standardized error handling.

  ## Parameters
  - `url` - The URL to fetch
  - `parser_fn` - Function to parse response body (defaults to Jason.decode/1)
  - `opts` - HTTP client options

  ## Returns
  - `{:ok, parsed_data}` - On success
  - `{:error, error}` - On failure

  ## Examples

  ```elixir
  # Simple JSON parsing
  {:ok, data} = Utils.fetch_json("https://api.example.com/data")

  # Custom parsing
  parser = &CustomParser.parse/1
  {:ok, data} = Utils.fetch_json(url, parser, timeout: 10_000)
  ```
  """
  @spec fetch_json(url(), parser_function(), opts()) :: {:ok, term()} | {:error, Error.t()}
  def fetch_json(url, parser_fn \\ &Jason.decode/1, opts \\ []) when is_function(parser_fn, 1) do
    Logger.debug("Fetching JSON from URL", url: url, opts: opts)

    case make_request("GET", url, opts) do
      {:ok, %{body: body}} when is_binary(body) ->
        case parser_fn.(body) do
          {:ok, parsed} ->
            Logger.debug("Successfully fetched and parsed JSON", url: url)
            {:ok, parsed}

          {:error, reason} ->
            Logger.error("Failed to parse response body", url: url, error: reason)

            {:error,
             Error.parsing_error(:json_decode, "Failed to parse JSON response", %{
               url: url,
               reason: reason
             })}
        end

      {:ok, response} ->
        Logger.error("Unexpected response format", url: url, response: inspect(response))

        {:error,
         Error.http_error(:unexpected_format, "Unexpected response format", false, %{
           url: url,
           response: response
         })}

      {:error, error} ->
        Logger.error("HTTP request failed", url: url, error: Error.message(error))
        {:error, error}
    end
  end

  @doc """
  Fetches raw binary data from a URL.

  ## Parameters
  - `url` - The URL to fetch
  - `opts` - HTTP client options

  ## Returns
  - `{:ok, binary_data}` - On success
  - `{:error, error}` - On failure

  ## Examples

  ```elixir
  {:ok, csv_data} = Utils.fetch_raw("https://example.com/data.csv")
  ```
  """
  @spec fetch_raw(url(), opts()) :: {:ok, binary()} | {:error, Error.t()}
  def fetch_raw(url, opts \\ []) do
    Logger.debug("Fetching raw data from URL", url: url, opts: opts)

    case make_request("GET", url, opts) do
      {:ok, %{body: body}} when is_binary(body) ->
        Logger.debug("Successfully fetched raw data", url: url, size: byte_size(body))
        {:ok, body}

      {:ok, response} ->
        Logger.error("Unexpected response format", url: url, response: inspect(response))

        {:error,
         Error.http_error(:unexpected_format, "Unexpected response format", false, %{
           url: url,
           response: response
         })}

      {:error, error} ->
        Logger.error("HTTP request failed", url: url, error: Error.message(error))
        {:error, error}
    end
  end

  # Telemetry and logging

  @doc """
  Wraps an HTTP request with telemetry and standardized error handling.

  ## Parameters
  - `method` - HTTP method
  - `url` - Request URL
  - `request_fn` - Function that performs the actual HTTP request

  ## Returns
  - Result from request_fn with telemetry tracking

  ## Examples

  ```elixir
  result = Utils.wrap_request("GET", url, fn ->
    HttpClient.get(url, opts)
  end)
  ```
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
          {:error, standardize_error(error, url)}
      catch
        thrown_value ->
          {:error, standardize_error(thrown_value, url)}
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, %{status: status}} ->
        Telemetry.http_request_stop(method, url, duration, status)

      {:error, error} ->
        Telemetry.http_request_error(method, url, duration, error)
    end

    result
  end

  # Private helpers

  @doc """
  Builds request options with default values and headers.

  ## Parameters
  - `opts` - Base options to merge with defaults

  ## Returns
  - Merged keyword list of options

  ## Examples

  ```elixir
  opts = Utils.build_request_opts([timeout: 10_000])
  ```
  """
  @spec build_request_opts(opts()) :: opts()
  def build_request_opts(opts) do
    default_opts = [
      headers: [
        {"user-agent",
         "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"}
      ],
      timeout: 5000
    ]

    # Merge headers specially to avoid overriding defaults
    custom_headers = Keyword.get(opts, :headers, [])
    default_headers = Keyword.get(default_opts, :headers, [])
    merged_headers = merge_headers(default_headers, custom_headers)

    opts
    |> Keyword.delete(:headers)
    |> Keyword.merge(Keyword.delete(default_opts, :headers))
    |> Keyword.put(:headers, merged_headers)
  end

  @doc """
  Merges default headers with custom headers.

  ## Parameters
  - `default_headers` - Default headers
  - `custom_headers` - Custom headers

  ## Returns
  - Merged headers list

  ## Examples

  ```elixir
  merged = Utils.merge_headers(defaults, customs)
  ```
  """
  @spec merge_headers(headers(), headers()) :: headers()
  def merge_headers(default_headers, custom_headers) do
    # Convert to maps for easier merging, then back to list
    default_map = Map.new(default_headers, fn {k, v} -> {String.downcase(k), {k, v}} end)
    custom_map = Map.new(custom_headers, fn {k, v} -> {String.downcase(k), {k, v}} end)

    Map.merge(custom_map, default_map)
    |> Map.values()
  end

  @doc """
  Determines if an HTTP response status is retryable.

  ## Parameters
  - `status` - HTTP status code

  ## Returns
  - `true` if retryable, `false` otherwise

  ## Examples

  ```elixir
  if Utils.retryable_status?(response.status) do
    # retry logic
  end
  ```
  """
  @spec retryable_status?(integer()) :: boolean()
  def retryable_status?(status) when status in [429, 500, 502, 503, 504], do: true
  def retryable_status?(_status), do: false

  @doc """
  Logs retry attempts with consistent formatting.

  ## Parameters
  - `attempt` - Current attempt number
  - `max_attempts` - Maximum attempts
  - `error` - Error that caused retry
  - `delay` - Delay before next attempt (ms)
  - `url` - URL being requested

  ## Examples

  ```elixir
  Utils.log_retry(2, 3, error, 1000, url)
  ```
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
end
