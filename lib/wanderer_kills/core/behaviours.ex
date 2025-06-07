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
    external service clients.
    """

    @type url :: String.t()
    @type headers :: [{String.t(), String.t()}]
    @type options :: keyword()
    @type response :: {:ok, map()} | {:error, Error.t()}

    @callback get(url(), headers(), options()) :: response()
    @callback post(url(), term(), headers(), options()) :: response()
    @callback put(url(), term(), headers(), options()) :: response()
    @callback delete(url(), headers(), options()) :: response()
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
  # Cache Store Behaviour
  # ============================================================================

  defmodule CacheStore do
    @moduledoc """
    Behaviour for cache store implementations.

    This behaviour standardizes cache operations across different cache
    implementations and storage backends.
    """

    @type cache_key :: term()
    @type cache_value :: term()
    @type ttl_seconds :: pos_integer()
    @type cache_result :: {:ok, cache_value()} | {:error, Error.t()}

    @callback get(cache_key()) :: cache_result()
    @callback put(cache_key(), cache_value()) :: :ok | {:error, Error.t()}
    @callback put_with_ttl(cache_key(), cache_value(), ttl_seconds()) :: :ok | {:error, Error.t()}
    @callback delete(cache_key()) :: :ok | {:error, Error.t()}
    @callback clear() :: :ok | {:error, Error.t()}
  end

  # ============================================================================
  # Parser Behaviour
  # ============================================================================

  defmodule Parser do
    @moduledoc """
    Behaviour for data parsing implementations.

    This behaviour standardizes parsing operations for killmails, ship types,
    and other structured data.
    """

    @type parse_input :: term()
    @type parse_result :: {:ok, term()} | {:error, Error.t()}

    @callback parse(parse_input()) :: parse_result()
    @callback validate(term()) :: boolean()
    @callback transform(term()) :: {:ok, term()} | {:error, Error.t()}
  end

  # ============================================================================
  # Event Handler Behaviour
  # ============================================================================

  defmodule EventHandler do
    @moduledoc """
    Behaviour for event handling implementations.

    This behaviour standardizes event processing for killmails, system events,
    and other application events.
    """

    @type event :: term()
    @type event_result :: :ok | {:error, Error.t()}

    @callback handle_event(event()) :: event_result()
    @callback can_handle?(event()) :: boolean()
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

  # ============================================================================
  # ZKB Client Behaviour
  # ============================================================================

  defmodule ZKBClient do
    @moduledoc """
    Behaviour for zKillboard client implementations.

    This behaviour standardizes interactions with the zKillboard API.
    """

    @type killmail_id :: pos_integer()
    @type system_id :: pos_integer()
    @type killmail_data :: map()
    @type zkb_result :: {:ok, killmail_data()} | {:error, Error.t()}

    @callback get_killmail(killmail_id()) :: zkb_result()
    @callback get_system_kills(system_id()) :: {:ok, [killmail_data()]} | {:error, Error.t()}
    @callback get_recent_kills() :: {:ok, [killmail_data()]} | {:error, Error.t()}
    @callback poll_redisq() :: {:ok, killmail_data() | nil} | {:error, Error.t()}
  end

  # ============================================================================
  # Enricher Behaviour
  # ============================================================================

  defmodule Enricher do
    @moduledoc """
    Behaviour for data enrichment implementations.

    This behaviour standardizes enrichment operations for killmails and other data.
    """

    @type enrichment_data :: term()
    @type enrichment_result :: {:ok, enrichment_data()} | {:error, Error.t()}

    @callback enrich(term()) :: enrichment_result()
    @callback enrich_batch([term()]) :: [enrichment_result()]
    @callback can_enrich?(term()) :: boolean()
  end

  # ============================================================================
  # Circuit Breaker Behaviour
  # ============================================================================

  defmodule CircuitBreaker do
    @moduledoc """
    Behaviour for circuit breaker implementations.

    This behaviour standardizes circuit breaker patterns for external service calls.
    """

    @type service_name :: atom()
    @type operation :: (-> {:ok, term()} | {:error, term()})
    @type circuit_result :: {:ok, term()} | {:error, Error.t()}

    @callback call(service_name(), operation()) :: circuit_result()
    @callback get_state(service_name()) :: :closed | :open | :half_open
    @callback reset(service_name()) :: :ok
  end

  # ============================================================================
  # Supervisor Child Behaviour
  # ============================================================================

  defmodule SupervisorChild do
    @moduledoc """
    Behaviour for supervisor child specifications.

    This behaviour standardizes child spec creation for GenServers and other processes.
    """

    @callback child_spec(keyword()) :: Supervisor.child_spec()
  end
end
