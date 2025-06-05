defmodule WandererKills.Cache do
  @moduledoc """
  Public API for the WandererKills Cache domain.

  This module provides a unified interface to cache operations including:
  - Killmail caching
  - System data caching
  - ESI data caching
  - Cache key management
  - Cache administration

  ## Usage

  ```elixir
  alias WandererKills.Cache

  # Store a killmail
  :ok = Cache.store_killmail(123456, killmail_data)

  # Get cached killmail
  {:ok, killmail} = Cache.get_killmail(123456)

  # Cache system data
  :ok = Cache.store_system_data(30000142, system_data)
  ```

  This reduces coupling between domains and provides a stable interface
  for cache operations across the application.
  """

  # Specialized Cache APIs
  alias WandererKills.Cache.Specialized.{KillmailCache, SystemCache, EsiCache}

  # Cache Infrastructure
  alias WandererKills.Cache.Key

  #
  # Killmail Cache API
  #

  @doc """
  Gets a killmail from the cache.
  """
  @spec get_killmail(integer()) :: {:ok, map()} | {:error, term()}
  def get_killmail(killmail_id) do
    KillmailCache.get_killmail(killmail_id)
  end

  @doc """
  Stores a killmail in the cache.
  """
  @spec store_killmail(integer(), map()) :: :ok | {:error, term()}
  def store_killmail(killmail_id, killmail_data) do
    KillmailCache.set_killmail(killmail_id, killmail_data)
  end

  @doc """
  Deletes a killmail from the cache.
  """
  @spec delete_killmail(integer()) :: :ok | {:error, term()}
  def delete_killmail(killmail_id) do
    KillmailCache.delete_killmail(killmail_id)
  end

  @doc """
  Gets all cached killmail IDs.
  """
  @spec get_killmail_ids() :: {:ok, [integer()]} | {:error, term()}
  def get_killmail_ids do
    KillmailCache.get_killmail_ids()
  end

  #
  # System Cache API
  #

  @doc """
  Gets system data from the cache.
  """
  @spec get_system_data(integer()) :: {:ok, map()} | {:error, term()}
  def get_system_data(system_id) do
    SystemCache.get_system_data(system_id)
  end

  @doc """
  Stores system data in the cache.
  """
  @spec store_system_data(integer(), map()) :: :ok | {:error, term()}
  def store_system_data(system_id, system_data) do
    SystemCache.cache_system_data(system_id, system_data)
  end

  @doc """
  Gets active systems from the cache.
  """
  @spec get_active_systems() :: {:ok, [integer()]} | {:error, term()}
  def get_active_systems do
    SystemCache.get_active_systems()
  end

  @doc """
  Checks if a system was recently fetched.
  """
  @spec recently_fetched?(integer()) :: boolean()
  def recently_fetched?(system_id) do
    SystemCache.recently_fetched?(system_id)
  end

  #
  # ESI Cache API
  #

  @doc """
  Gets character information from ESI cache.
  """
  @spec get_character_info(integer()) :: {:ok, map()} | {:error, term()}
  def get_character_info(character_id) do
    EsiCache.get_character_info(character_id)
  end

  @doc """
  Gets corporation information from ESI cache.
  """
  @spec get_corporation_info(integer()) :: {:ok, map()} | {:error, term()}
  def get_corporation_info(corporation_id) do
    EsiCache.get_corporation_info(corporation_id)
  end

  @doc """
  Gets alliance information from ESI cache.
  """
  @spec get_alliance_info(integer()) :: {:ok, map()} | {:error, term()}
  def get_alliance_info(alliance_id) do
    EsiCache.get_alliance_info(alliance_id)
  end

  @doc """
  Gets ship type information from ESI cache.
  """
  @spec get_type_info(integer()) :: {:ok, map()} | {:error, term()}
  def get_type_info(type_id) do
    EsiCache.get_type_info(type_id)
  end

  @doc """
  Ensures data is cached for the specified entity type and ID.
  """
  @spec ensure_cached(atom(), integer()) :: :ok | {:error, term()}
  def ensure_cached(type, id) do
    EsiCache.ensure_cached(type, id)
  end

  #
  # Cache Administration API
  #

  @doc """
  Clears all cache entries.
  """
  @spec clear_all() :: :ok
  def clear_all do
    KillmailCache.clear()
    SystemCache.clear()
    EsiCache.clear()
    :ok
  end

  @doc """
  Clears cache entries for a specific type.
  """
  @spec clear(atom()) :: :ok | {:error, term()}
  def clear(:killmails), do: KillmailCache.clear()
  def clear(:system), do: SystemCache.clear()
  def clear(:esi), do: EsiCache.clear()
  def clear(_), do: {:error, :invalid_cache_type}

  @doc """
  Generates cache keys using the Key module.
  """
  @spec generate_key(atom(), [String.t()]) :: String.t()
  def generate_key(cache_type, parts) do
    Key.generate(cache_type, parts)
  end

  @doc """
  Gets TTL for a cache type.
  """
  @spec get_ttl(atom()) :: pos_integer()
  def get_ttl(cache_type) do
    Key.get_ttl(cache_type)
  end

  #
  # Type Definitions
  #

  @type cache_type :: :killmails | :system | :esi
  @type cache_result :: {:ok, term()} | {:error, term()}
  @type cache_status :: :ok | {:error, term()}
end
