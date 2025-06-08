defmodule WandererKills.Behaviours.HttpClient do
  @moduledoc """
  Behaviour for HTTP client implementations.

  This behaviour standardizes HTTP operations across ESI, ZKB, and other
  external service clients. Currently only GET operations are used.
  """

  alias WandererKills.Infrastructure.Error

  @type url :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type options :: keyword()
  @type response :: {:ok, map()} | {:error, Error.t()}

  @callback get(url(), headers(), options()) :: response()
  @callback get_with_rate_limit(url(), options()) :: response()
end
