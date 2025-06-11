defmodule WandererKills.Http.ClientBehaviour do
  @moduledoc """
  Behaviour for HTTP client implementations.

  This behaviour standardizes HTTP operations across ESI, ZKB, and other
  external service clients. Supports both GET and POST operations.
  """

  alias WandererKills.Support.Error

  @type url :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type options :: keyword()
  @type response :: {:ok, map()} | {:error, Error.t()}

  @callback get(url(), headers(), options()) :: response()
  @callback get_with_rate_limit(url(), options()) :: response()
  @callback post(url(), map(), options()) :: response()
end
