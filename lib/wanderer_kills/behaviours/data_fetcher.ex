defmodule WandererKills.Behaviours.DataFetcher do
  @moduledoc """
  Behaviour for data fetching implementations.

  This behaviour standardizes data fetching operations for ESI, ZKB,
  and other external data sources.
  """

  alias WandererKills.Infrastructure.Error

  @type fetch_args :: term()
  @type fetch_result :: {:ok, term()} | {:error, Error.t()}

  @callback fetch(fetch_args()) :: fetch_result()
  @callback fetch_many([fetch_args()]) :: [fetch_result()]
  @callback supports?(fetch_args()) :: boolean()
end
