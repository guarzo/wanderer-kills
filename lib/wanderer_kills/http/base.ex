defmodule WandererKills.Http.Base do
  @moduledoc """
  Base HTTP functionality shared across all HTTP client implementations.

  This module provides common patterns for:
  - Status code handling
  - Error response mapping
  - Retry logic configuration
  - Telemetry integration
  - Request/response validation
  """

  require Logger
  alias WandererKills.Support.Error
  alias WandererKills.Config

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

  @doc """
  Maps HTTP status codes to standardized error responses.

  ## Examples
      iex> WandererKills.Http.Base.map_status_code(200)
      :ok

      iex> WandererKills.Http.Base.map_status_code(404)
      {:error, :not_found}

      iex> WandererKills.Http.Base.map_status_code(429)
      {:error, :rate_limited}

      iex> WandererKills.Http.Base.map_status_code(500)
      {:error, {:server_error, 500}}
  """
  @spec map_status_code(status_code()) :: :ok | {:error, term()}
  def map_status_code(status) when status in @success_range, do: :ok
  def map_status_code(@not_found), do: {:error, :not_found}
  def map_status_code(@rate_limited), do: {:error, :rate_limited}

  def map_status_code(status) when status in @server_error_range,
    do: {:error, {:server_error, status}}

  def map_status_code(status) when status in @client_error_range,
    do: {:error, {:client_error, status}}

  def map_status_code(status), do: {:error, {:http_error, status}}

  @doc """
  Determines if an HTTP error is retryable.

  Server errors (5xx) and rate limiting (429) are considered retryable.
  Client errors (4xx) except rate limiting are not retryable.
  """
  @spec retryable_error?(term()) :: boolean()
  def retryable_error?({:error, :rate_limited}), do: true
  def retryable_error?({:error, {:server_error, _}}), do: true
  def retryable_error?({:error, {:client_error, _}}), do: false
  def retryable_error?({:error, :not_found}), do: false
  def retryable_error?(_), do: false

  @doc """
  Wraps an HTTP operation with telemetry events.

  Emits start and stop events with appropriate metadata.
  """
  def with_telemetry(method, url, metadata \\ [], fun) do
    start_metadata = Keyword.merge([method: method, url: url], metadata)
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:wanderer_kills, :http, :request, :start],
      %{system_time: System.system_time()},
      Map.new(start_metadata)
    )

    try do
      result = fun.()
      duration_native = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration_native, :native, :millisecond)

      # Extract service from metadata or URL
      service = Keyword.get(metadata, :service, :http)

      case result do
        {:ok, %{status: status}} ->
          # Record success in unified metrics
          WandererKills.Observability.Metrics.record_http_request(
            service,
            method,
            status,
            duration_ms,
            Map.new(metadata)
          )

        {:error, reason} ->
          # Record failure in unified metrics
          WandererKills.Observability.Metrics.record_failure(service, method, reason)
      end

      result
    rescue
      error ->
        service = Keyword.get(metadata, :service, :http)

        # Record error in unified metrics
        WandererKills.Observability.Metrics.record_failure(service, method, :exception)

        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Configures retry options for a service.

  Returns a keyword list of retry options based on service configuration.
  """
  @spec retry_options(atom(), keyword()) :: keyword()
  def retry_options(service, opts \\ []) do
    config = Config.retry()

    base_options = [
      max_retries: config.http_max_retries,
      base_delay: config.http_base_delay,
      max_delay: config.http_max_delay,
      retry?: &retryable_error?/1
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

  @doc """
  Validates required fields in a response.

  Returns an error if any required fields are missing.
  """
  @spec validate_required_fields(map(), [atom() | String.t()]) :: :ok | {:error, term()}
  def validate_required_fields(response, required_fields) when is_map(response) do
    missing_fields =
      Enum.filter(required_fields, fn field ->
        field_key = to_string(field)
        not Map.has_key?(response, field_key) and not Map.has_key?(response, field)
      end)

    case missing_fields do
      [] ->
        :ok

      fields ->
        {:error,
         Error.validation_error(:missing_fields, "Missing required fields", %{fields: fields})}
    end
  end

  def validate_required_fields(_, _),
    do: {:error, Error.validation_error(:invalid_response, "Response must be a map")}

  @doc """
  Standard JSON parsing with error handling.

  Handles both pre-parsed (map/list) and raw (binary) responses.
  """
  @spec parse_json(response_body()) :: {:ok, term()} | {:error, term()}
  def parse_json(body) when is_map(body) or is_list(body), do: {:ok, body}

  def parse_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, reason} ->
        {:error, Error.parsing_error(:invalid_json, "Invalid JSON response", %{reason: reason})}
    end
  end

  def parse_json(_),
    do:
      {:error,
       Error.parsing_error(:invalid_response_type, "Response body must be string, map, or list")}

  @doc """
  Logs HTTP errors with consistent format.
  """
  @spec log_http_error(String.t(), String.t(), term(), keyword()) :: :ok
  def log_http_error(service, operation, error, metadata \\ []) do
    Logger.error(
      "[#{service}] #{operation} failed",
      Keyword.merge(
        [
          service: service,
          operation: operation,
          error: inspect(error)
        ],
        metadata
      )
    )
  end

  @doc """
  Builds common HTTP headers.
  """
  @spec common_headers(keyword()) :: [{String.t(), String.t()}]
  def common_headers(opts \\ []) do
    base_headers = [
      {"user-agent", "WandererKills/1.0"},
      {"accept", "application/json"}
    ]

    custom_headers = Keyword.get(opts, :headers, [])
    Enum.uniq_by(custom_headers ++ base_headers, fn {key, _} -> String.downcase(key) end)
  end
end
