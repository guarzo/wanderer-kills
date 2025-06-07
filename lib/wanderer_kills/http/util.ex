defmodule WandererKills.Http.Util do
  @moduledoc """
  Shared HTTP utilities for consistent request handling across clients.

  This module provides common patterns for HTTP operations used by both
  ESI and ZKB clients, reducing duplication and ensuring consistency.
  """

  require Logger
  alias WandererKills.Infrastructure.{Config, Error}
  alias WandererKills.Http.Client
  alias WandererKills.Observability.Telemetry

  @type url :: String.t()
  @type params :: keyword()
  @type headers :: [{String.t(), String.t()}]
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Standard request with telemetry and error handling.

  Provides consistent request patterns with automatic telemetry,
  logging, and error handling across all HTTP clients.
  """
  @spec request_with_telemetry(url(), atom(), keyword()) :: response()
  def request_with_telemetry(url, service, opts \\ []) do
    operation = Keyword.get(opts, :operation, :http_request)
    headers = Keyword.get(opts, :headers, [])
    params = Keyword.get(opts, :params, [])
    timeout = Keyword.get(opts, :timeout, Config.timeouts().default_request_ms)

    Logger.debug("Starting HTTP request",
      url: url,
      service: service,
      operation: operation
    )

    Telemetry.http_request_start("GET", url)
    start_time = System.monotonic_time()

    request_opts = [
      headers: headers,
      params: params,
      timeout: timeout,
      recv_timeout: timeout
    ]

    result = Client.get_with_rate_limit(url, request_opts)
    duration = System.monotonic_time() - start_time

    case result do
      {:ok, response} ->
        Telemetry.http_request_stop("GET", url, duration, response.status)

        Logger.debug("HTTP request successful",
          url: url,
          service: service,
          operation: operation,
          status: response.status
        )

        {:ok, response}

      {:error, reason} ->
        Telemetry.http_request_error("GET", url, duration, reason)

        Logger.error("HTTP request failed",
          url: url,
          service: service,
          operation: operation,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @doc """
  Parse JSON response with error handling.

  Provides consistent JSON parsing across all HTTP clients.
  """
  @spec parse_json_response(map()) :: {:ok, term()} | {:error, term()}
  def parse_json_response(%{status: 200, body: body}) when is_map(body) or is_list(body) do
    {:ok, body}
  end

  def parse_json_response(%{status: 200, body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, reason} ->
        {:error, Error.parsing_error("Invalid JSON response", %{reason: reason})}
    end
  end

  def parse_json_response(%{status: 404}) do
    {:error, :not_found}
  end

  def parse_json_response(%{status: 429}) do
    {:error, :rate_limited}
  end

  def parse_json_response(%{status: status}) when status >= 500 do
    {:error, Error.http_error("Server error", %{status: status})}
  end

  def parse_json_response(%{status: status}) do
    {:error, Error.http_error("HTTP error", %{status: status})}
  end

  @doc """
  Build query parameters string.

  Provides consistent parameter handling across clients.
  """
  @spec build_query_params(keyword()) :: keyword()
  def build_query_params(params) do
    params
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn
      {key, true} -> {key, "true"}
      {key, false} -> {key, "false"}
      {key, value} when is_integer(value) -> {key, Integer.to_string(value)}
      {key, value} -> {key, value}
    end)
  end

  @doc """
  Standard headers for EVE Online API requests.
  """
  @spec eve_api_headers(String.t()) :: headers()
  def eve_api_headers(user_agent \\ default_user_agent()) do
    [
      {"User-Agent", user_agent},
      {"Accept", "application/json"},
      {"Accept-Encoding", "gzip"}
    ]
  end

  @doc """
  Retry an operation with specific service configuration.
  """
  @spec retry_operation((-> term()), atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def retry_operation(fun, service, opts \\ []) do
    operation_name = Keyword.get(opts, :operation_name, "#{service} request")
    max_retries = Keyword.get(opts, :max_retries, Config.retry().http_max_retries)

    WandererKills.Infrastructure.Retry.retry_http_operation(fun,
      operation_name: operation_name,
      max_retries: max_retries
    )
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
      [] -> {:ok, data}
      missing -> {:error, Error.validation_error("Missing required fields", %{missing: missing})}
    end
  end

  def validate_response_structure(data, _required_fields) when is_list(data) do
    {:ok, data}
  end

  def validate_response_structure(data, _required_fields) do
    {:error, Error.validation_error("Invalid response format", %{type: typeof(data)})}
  end

  # Private functions

  defp default_user_agent do
    "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"
  end

  defp typeof(data) when is_map(data), do: :map
  defp typeof(data) when is_list(data), do: :list
  defp typeof(data) when is_binary(data), do: :string
  defp typeof(data) when is_integer(data), do: :integer
  defp typeof(data) when is_float(data), do: :float
  defp typeof(data) when is_boolean(data), do: :boolean
  defp typeof(data) when is_atom(data), do: :atom
  defp typeof(_), do: :unknown
end
