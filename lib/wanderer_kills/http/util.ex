defmodule WandererKills.Http.Util do
  @moduledoc """
  Utility functions for HTTP requests and response handling.

  This module provides helper functions for:
  - Building request options
  - Handling HTTP responses and errors
  - Logging and error reporting

  ## Usage

  ```elixir
  # Build request options
  opts = Util.build_request_opts([
    params: [query: "value"],
    headers: [{"authorization", "Bearer token"}]
  ])

  # Handle HTTP response
  case Util.handle_http_response(response) do
    {:ok, data} -> process_data(data)
    {:error, reason} -> handle_error(reason)
  end
  ```

  ## Error Handling

  The module provides comprehensive error handling:
  - Detailed error logging
  - Rate limit detection and handling
  - Delegates to WandererKills.Http.Retry for retry logic
  """

  require Logger
  alias WandererKills.Http.{Retry, Client}

  @type url :: String.t()
  @type opts :: keyword()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Builds request options with default values and headers.

  ## Parameters
  - `opts` - Base options to merge with defaults

  ## Returns
  Keyword list of request options including:
  - Default headers
  - Timeout settings
  - Rate limiting configuration
  - Any custom options provided

  ## Examples

  ```elixir
  # Basic options
  opts = build_request_opts([])

  # With custom options
  opts = build_request_opts([
    params: [query: "value"],
    headers: [{"authorization", "Bearer token"}]
  ])
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

    Keyword.merge(default_opts, opts)
  end

  @doc """
  Handles HTTP response and converts to standard format.

  This function delegates to the centralized status code handling
  in WandererKills.Http.Client for consistency across all HTTP clients.

  ## Parameters
  - `response` - HTTP response from Req
  - `client` - Optional client module (defaults to WandererKills.Http.Client)

  ## Returns
  - `{:ok, data}` - On success, data is either parsed JSON or raw body
  - `{:error, reason}` - On failure, with appropriate error reason

  ## Examples

  ```elixir
  # Success case
  {:ok, %{status: 200, body: body}} = response
  {:ok, data} = handle_http_response(response)

  # Error case
  {:ok, %{status: 404}} = response
  {:error, :not_found} = handle_http_response(response)
  ```
  """
  @spec handle_http_response(Req.Response.t(), module()) :: response()
  def handle_http_response(response, client \\ Client) do
    case client.handle_status_code(response.status, response) do
      {:ok, _} -> {:ok, response.body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Handles HTTP errors with logging.

  ## Parameters
  - `reason` - Error reason
  - `url` - URL that failed

  ## Returns
  - `{:error, reason}` - Processed error reason

  ## Examples

  ```elixir
  # Network error
  {:error, %ConnectionError{}} = error
  {:error, :connection_failed} = handle_http_error(error, "https://api.example.com")

  # Timeout error
  {:error, %TimeoutError{}} = error
  {:error, :timeout} = handle_http_error(error, "https://api.example.com")
  ```
  """
  @spec handle_http_error(term(), url()) :: {:error, term()}
  def handle_http_error(reason, url) do
    if Retry.retriable_error?(reason) do
      log_retriable_error(reason, url)
    else
      Logger.error("Request failed for #{url}: #{inspect(reason)}")
    end

    {:error, reason}
  end

  @doc """
  Logs a retriable error with appropriate context.
  """
  @spec log_retriable_error(term(), url()) :: :ok
  def log_retriable_error(:rate_limited, url) do
    Logger.warning("Rate limited for #{url}, will retry")
  end

  def log_retriable_error(reason, url) do
    Logger.warning("Request failed for #{url}, will retry: #{inspect(reason)}")
  end
end
