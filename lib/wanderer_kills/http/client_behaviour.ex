defmodule WandererKills.Http.ClientBehaviour do
  @moduledoc """
  Behaviour for HTTP client.

  This behaviour defines the interface that HTTP client implementations
  must follow. It aligns with the actual functions implemented in
  WandererKills.Http.Client.
  """

  @type url :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type opts :: keyword()
  @type response :: {:ok, map()} | {:error, term()}

  @doc """
  Makes a GET request with rate limiting and retries.

  ## Parameters
    - `url` - The URL to request
    - `opts` - Options including headers, params, timeout, etc.

  ## Returns
    - `{:ok, response}` - On success
    - `{:error, reason}` - On failure
  """
  @callback get_with_rate_limit(url(), opts()) :: response()

  @doc """
  Centralized HTTP status code handling.

  ## Parameters
  - `status` - HTTP status code
  - `response` - HTTP response map (optional, defaults to empty map)

  ## Returns
  - `{:ok, response}` - For successful status codes
  - `{:error, reason}` - For error status codes
  """
  @callback handle_status_code(integer(), map()) :: {:ok, map()} | {:error, term()}
end
