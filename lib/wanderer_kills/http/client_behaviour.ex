defmodule WandererKills.Http.ClientBehaviour do
  @moduledoc """
  Behaviour for HTTP client implementations.

  This behaviour standardizes HTTP operations across ESI, ZKB, and other
  external service clients. It provides a consistent interface for HTTP
  operations with built-in rate limiting, retries, and error handling.

  ## Implementation Notes

  Implementations of this behaviour should:
  - Handle rate limiting (429 responses) appropriately
  - Retry transient failures with exponential backoff
  - Return standardized error responses using `WandererKills.Support.Error`
  - Parse JSON responses automatically unless `:raw` option is set
  - Emit telemetry events for monitoring

  ## Example Implementation

      defmodule MyHttpClient do
        @behaviour WandererKills.Http.ClientBehaviour

        @impl true
        def get(url, headers, options) do
          # Implementation with retries and error handling
        end
      end
  """

  alias WandererKills.Support.Error

  @typedoc "HTTP URL string"
  @type url :: String.t()

  @typedoc "HTTP headers as key-value pairs"
  @type headers :: [{String.t(), String.t()}]

  @typedoc """
  Request options:
  - `:params` - Query parameters (keyword list or map)
  - `:timeout` - Request timeout in milliseconds
  - `:raw` - If true, return raw response without JSON parsing
  - `:retries` - Number of retry attempts
  """
  @type options :: keyword()

  @typedoc "HTTP response body (parsed JSON or raw binary)"
  @type response_body :: map() | list() | binary()

  @typedoc "Standard response tuple"
  @type response :: {:ok, response_body()} | {:error, Error.t()}

  @doc """
  Performs a GET request.

  ## Parameters
  - `url` - The URL to request
  - `headers` - Additional HTTP headers
  - `options` - Request options

  ## Returns
  - `{:ok, body}` - Successful response with parsed body
  - `{:error, error}` - Error with standardized error struct
  """
  @callback get(url(), headers(), options()) :: response()

  @doc """
  Performs a GET request with built-in rate limiting.

  This is the preferred method for external API calls as it handles
  rate limiting automatically.

  ## Parameters
  - `url` - The URL to request
  - `options` - Request options (headers should be in options)

  ## Returns
  - `{:ok, body}` - Successful response with parsed body
  - `{:error, error}` - Error with standardized error struct
  """
  @callback get_with_rate_limit(url(), options()) :: response()

  @doc """
  Performs a POST request with JSON body.

  ## Parameters
  - `url` - The URL to post to
  - `body` - The request body (will be JSON encoded)
  - `options` - Request options

  ## Returns
  - `{:ok, response_body}` - Successful response with parsed body
  - `{:error, error}` - Error with standardized error struct
  """
  @callback post(url(), map(), options()) :: response()
end
