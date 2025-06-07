defmodule WandererKills.Core.Http do
  @moduledoc """
  Public API for the WandererKills HTTP domain.

  This module provides a unified interface to HTTP operations including:
  - HTTP client operations
  - Rate limiting
  - Error handling

  ## Usage

  ```elixir
  alias WandererKills.Core.Http

  # Make a GET request with rate limiting
  {:ok, response} = Http.get_with_rate_limit(url)

  # Check if an error is retriable
  true = Http.retriable_error?(:timeout)
  ```

  This reduces coupling between domains and provides a stable interface
  for HTTP operations across the application.
  """

  # HTTP Client API
  alias WandererKills.Core.Http.ClientProvider

  #
  # Client API
  #

  @doc """
  Makes a GET request with rate limiting.
  """
  @spec get_with_rate_limit(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_with_rate_limit(url, opts \\ []) do
    client().get_with_rate_limit(url, opts)
  end

  @doc """
  Makes a basic GET request without rate limiting.
  """
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get(url, opts \\ []) do
    client().get(url, opts)
  end

  @doc """
  Makes a POST request.
  """
  @spec post(String.t(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def post(url, body, opts \\ []) do
    client().post(url, body, opts)
  end

  @doc """
  Handles HTTP status codes and returns appropriate responses.
  """
  @spec handle_status_code(integer(), map()) :: {:ok, term()} | {:error, term()}
  def handle_status_code(status_code, response) do
    client().handle_status_code(status_code, response)
  end

  #
  # Error Handling API
  #

  @doc """
  Checks if an HTTP error is retriable.
  """
  @spec retriable_error?(term()) :: boolean()
  def retriable_error?(error) do
    case error do
      :timeout -> true
      :rate_limited -> true
      :connection_failed -> true
      {:http_error, status} when status in [408, 429, 500, 502, 503, 504] -> true
      _ -> false
    end
  end

  #
  # Configuration API
  #

  @doc """
  Gets the current HTTP client module.
  """
  @spec client() :: module()
  def client do
    ClientProvider.get()
  end

  #
  # Utility Functions
  #

  @doc """
  Safely parses JSON response body.
  """
  @spec parse_json(String.t()) :: {:ok, term()} | {:error, term()}
  def parse_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def parse_json(_), do: {:error, :invalid_input}

  @doc """
  Normalizes HTTP headers to lowercase keys.
  """
  @spec normalize_headers(map() | list()) :: map()
  def normalize_headers(headers) when is_list(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), v} end)
    |> Enum.into(%{})
  end

  def normalize_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), v} end)
    |> Enum.into(%{})
  end

  #
  # Type Definitions
  #

  @type http_response :: {:ok, map()} | {:error, term()}
  @type http_method :: :get | :post | :put | :delete
  @type http_headers :: map() | keyword()
  @type http_body :: String.t() | map() | keyword()
end
