defmodule WandererKills.Data.Sources.HttpClient do
  @moduledoc """
  Behaviour for making HTTP requests.
  """

  @callback get(url :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback post(url :: String.t(), body :: map()) :: {:ok, map()} | {:error, term()}
end
