defmodule WandererKills.Http.ClientUtil do
  @moduledoc """
  Utility functions for standardized HTTP request patterns.

  This module provides common HTTP request patterns to reduce boilerplate
  code across modules that make HTTP requests.
  """

  require Logger
  alias WandererKills.Http.ClientProvider

  @type parser_function :: (binary() -> {:ok, term()} | {:error, term()})
  @type http_opts :: keyword()
  @type fetch_result :: {:ok, term()} | {:error, term()}

  @doc """
  Fetches JSON data from a URL with standardized error handling.

  ## Parameters
  - `url` - The URL to fetch
  - `parser_fn` - Function to parse the response body
  - `opts` - HTTP client options (default: [])

  ## Returns
  - `{:ok, parsed_data}` - On successful fetch and parse
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  # Simple JSON parsing
  parser = &Jason.decode/1
  {:ok, data} = fetch_json("https://api.example.com/data", parser)

  # Custom parsing with validation
  parser = fn body ->
    with {:ok, json} <- Jason.decode(body),
         {:ok, validated} <- validate_response(json) do
      {:ok, validated}
    end
  end
  {:ok, data} = fetch_json("https://api.example.com/data", parser, timeout: 10_000)
  ```
  """
  @spec fetch_json(String.t(), parser_function(), http_opts()) :: fetch_result()
  def fetch_json(url, parser_fn, opts \\ []) when is_function(parser_fn, 1) do
    Logger.debug("Fetching JSON from URL", url: url, opts: opts)

    case ClientProvider.get().get_with_rate_limit(url, opts) do
      {:ok, %{body: body}} when is_binary(body) ->
        case parser_fn.(body) do
          {:ok, parsed} ->
            Logger.debug("Successfully fetched and parsed JSON", url: url)
            {:ok, parsed}

          {:error, reason} ->
            Logger.error("Failed to parse response body", url: url, error: reason)
            {:error, {:parse_error, reason}}
        end

      {:ok, response} ->
        Logger.error("Unexpected response format", url: url, response: inspect(response))
        {:error, :unexpected_response_format}

      {:error, reason} ->
        Logger.error("HTTP request failed", url: url, error: reason)
        {:error, reason}
    end
  end

  @doc """
  Fetches raw binary data from a URL with standardized error handling.

  ## Parameters
  - `url` - The URL to fetch
  - `opts` - HTTP client options (default: [])

  ## Returns
  - `{:ok, binary_data}` - On successful fetch
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, csv_data} = fetch_raw("https://example.com/data.csv", raw: true)
  {:ok, image_data} = fetch_raw("https://example.com/image.png")
  ```
  """
  @spec fetch_raw(String.t(), http_opts()) :: {:ok, binary()} | {:error, term()}
  def fetch_raw(url, opts \\ []) do
    Logger.debug("Fetching raw data from URL", url: url, opts: opts)

    case ClientProvider.get().get_with_rate_limit(url, opts) do
      {:ok, %{body: body}} when is_binary(body) ->
        Logger.debug("Successfully fetched raw data", url: url, size: byte_size(body))
        {:ok, body}

      {:ok, response} ->
        Logger.error("Unexpected response format", url: url, response: inspect(response))
        {:error, :unexpected_response_format}

      {:error, reason} ->
        Logger.error("HTTP request failed", url: url, error: reason)
        {:error, reason}
    end
  end

  @doc """
  Fetches and processes data with a custom handler function.

  This is the most flexible option for custom response processing.

  ## Parameters
  - `url` - The URL to fetch
  - `handler_fn` - Function to process the HTTP response
  - `opts` - HTTP client options (default: [])

  ## Returns
  - Result from the handler function

  ## Examples

  ```elixir
  # Custom response handler
  handler = fn response ->
    case response do
      {:ok, %{status: 200, body: body}} -> process_success(body)
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  result = fetch_with_handler("https://api.example.com/data", handler)
  ```
  """
  @spec fetch_with_handler(String.t(), function(), http_opts()) :: term()
  def fetch_with_handler(url, handler_fn, opts \\ []) when is_function(handler_fn, 1) do
    Logger.debug("Fetching with custom handler", url: url, opts: opts)

    response = ClientProvider.get().get_with_rate_limit(url, opts)
    handler_fn.(response)
  end

  @doc """
  Standard JSON parser using Jason.

  This is a convenience function for the most common JSON parsing case.

  ## Examples

  ```elixir
  {:ok, data} = fetch_json("https://api.example.com/data", &ClientUtil.parse_json/1)
  ```
  """
  @spec parse_json(binary()) :: {:ok, term()} | {:error, term()}
  def parse_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  @doc """
  Creates a simple success/error handler for HTTP responses.

  Returns a function that can be used with `fetch_with_handler/3`.

  ## Parameters
  - `success_fn` - Function to call on successful response (status 200-299)
  - `error_fn` - Function to call on error response (optional)

  ## Examples

  ```elixir
  handler = create_response_handler(
    &Jason.decode/1,
    fn status -> {:error, {:http_error, status}} end
  )

  result = fetch_with_handler("https://api.example.com/data", handler)
  ```
  """
  @spec create_response_handler(function(), function() | nil) :: function()
  def create_response_handler(success_fn, error_fn \\ nil) when is_function(success_fn, 1) do
    default_error_fn = fn
      %{status: status} -> {:error, {:http_error, status}}
      reason -> {:error, reason}
    end

    error_handler = error_fn || default_error_fn

    fn
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        success_fn.(body)

      {:ok, response} ->
        error_handler.(response)

      {:error, reason} ->
        error_handler.(reason)
    end
  end
end
