defmodule WandererKills.Core.Behaviours do
  @moduledoc """
  Shared behaviours for WandererKills application patterns.

  This module defines common behaviours that standardize interfaces across
  different modules, reducing ad-hoc code and improving consistency.
  """

  alias WandererKills.Core.Error

  # ============================================================================
  # HTTP Client Behaviour
  # ============================================================================

  defmodule HttpClient do
    @moduledoc """
    Behaviour for HTTP client implementations.

    This behaviour standardizes HTTP operations across ESI, ZKB, and other
    external service clients. Currently only GET operations are used.
    """

    @type url :: String.t()
    @type headers :: [{String.t(), String.t()}]
    @type options :: keyword()
    @type response :: {:ok, map()} | {:error, Error.t()}

    @callback get(url(), headers(), options()) :: response()
    @callback get_with_rate_limit(url(), options()) :: response()
  end

  # ============================================================================
  # Data Fetcher Behaviour
  # ============================================================================

  defmodule DataFetcher do
    @moduledoc """
    Behaviour for data fetching implementations.

    This behaviour standardizes data fetching operations for ESI, ZKB,
    and other external data sources.
    """

    @type fetch_args :: term()
    @type fetch_result :: {:ok, term()} | {:error, Error.t()}

    @callback fetch(fetch_args()) :: fetch_result()
    @callback fetch_many([fetch_args()]) :: [fetch_result()]
    @callback supports?(fetch_args()) :: boolean()
  end

  # ============================================================================
  # ESI Client Behaviour
  # ============================================================================

  defmodule ESIClient do
    @moduledoc """
    Behaviour for ESI (EVE Swagger Interface) client implementations.

    This behaviour standardizes interactions with the EVE Online ESI API.
    """

    @type entity_id :: pos_integer()
    @type entity_data :: map()
    @type esi_result :: {:ok, entity_data()} | {:error, Error.t()}

    # Character operations
    @callback get_character(entity_id()) :: esi_result()
    @callback get_character_batch([entity_id()]) :: [esi_result()]

    # Corporation operations
    @callback get_corporation(entity_id()) :: esi_result()
    @callback get_corporation_batch([entity_id()]) :: [esi_result()]

    # Alliance operations
    @callback get_alliance(entity_id()) :: esi_result()
    @callback get_alliance_batch([entity_id()]) :: [esi_result()]

    # Type operations
    @callback get_type(entity_id()) :: esi_result()
    @callback get_type_batch([entity_id()]) :: [esi_result()]

    # Group operations
    @callback get_group(entity_id()) :: esi_result()
    @callback get_group_batch([entity_id()]) :: [esi_result()]

    # System operations
    @callback get_system(entity_id()) :: esi_result()
    @callback get_system_batch([entity_id()]) :: [esi_result()]
  end
end
