defmodule WandererKills.Cache do
  @moduledoc """
  Unified cache interface for the WandererKills application.

  This module provides a single entry point for all cache operations,
  reducing module dependencies by delegating to specialized cache
  implementations while maintaining a consistent API.

  ## Features

  - Unified interface for all cache types (killmails, system, ESI)
  - Consistent error handling and return patterns
  - Reduced module coupling through single dependency
  - Type-safe operations with proper specs

  ## Usage

  ```elixir
  # Killmail operations
  {:ok, killmail} = Cache.get_killmail(123)
  :ok = Cache.set_killmail(123, killmail_data)

  # System operations
  {:ok, system_ids} = Cache.get_active_systems()
  :ok = Cache.increment_system_kill_count(30000142)

  # ESI operations
  {:ok, character} = Cache.get_character_info(123456)
  {:ok, type_info} = Cache.get_type_info(456)
  ```

  ## Architecture

  This module acts as a facade, delegating to specialized cache modules:
  - `KillmailCache` for killmail-related operations
  - `SystemCache` for system-related operations
  - `EsiCache` for ESI data operations

  All operations return consistent `{:ok, result} | {:error, reason}` tuples.
  """

  require Logger

  # Import specialized cache modules
  alias WandererKills.Cache.Specialized.{KillmailCache, SystemCache, EsiCache}

  # Type definitions
  @type cache_type :: :killmails | :system | :esi
  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type character_id :: pos_integer()
  @type corporation_id :: pos_integer()
  @type alliance_id :: pos_integer()
  @type type_id :: pos_integer()
  @type killmail :: map()
  @type system_data :: map()
  @type cache_result :: {:ok, term()} | {:error, term()}

  # ===== KILLMAIL CACHE OPERATIONS =====

  @doc """
  Gets a killmail by ID from the cache.
  """
  @spec get_killmail(killmail_id()) :: {:ok, killmail()} | {:error, term()}
  def get_killmail(killmail_id), do: KillmailCache.get_killmail(killmail_id)

  @doc """
  Sets a killmail in the cache.
  """
  @spec set_killmail(killmail_id(), killmail()) :: :ok | {:error, term()}
  def set_killmail(killmail_id, killmail), do: KillmailCache.set_killmail(killmail_id, killmail)

  @doc """
  Gets all killmails for a system - delegates to system cache.
  """
  @spec get_system_killmails(system_id()) :: {:ok, [killmail_id()]} | {:error, term()}
  def get_system_killmails(system_id), do: SystemCache.get_killmails(system_id)

  @doc """
  Gets killmail IDs for a system - alias for get_system_killmails for backward compatibility.
  """
  @spec get_system_killmail_ids(system_id()) :: {:ok, [killmail_id()]} | {:error, term()}
  def get_system_killmail_ids(system_id), do: SystemCache.get_killmail_ids(system_id)

  @doc """
  Adds a killmail to a system's killmail list.
  """
  @spec add_system_killmail(system_id(), killmail_id()) :: :ok | {:error, term()}
  def add_system_killmail(system_id, killmail_id) do
    SystemCache.add_killmail(system_id, killmail_id)
  end

  @doc "Placeholder for character killmails - not implemented in specialized cache"
  def get_character_killmails(_character_id), do: {:error, :not_implemented}

  @doc "Placeholder for character killmails - not implemented in specialized cache"
  def add_character_killmail(_character_id, _killmail_id), do: {:error, :not_implemented}

  @doc "Placeholder for corporation killmails - not implemented in specialized cache"
  def get_corporation_killmails(_corporation_id), do: {:error, :not_implemented}

  @doc "Placeholder for corporation killmails - not implemented in specialized cache"
  def add_corporation_killmail(_corporation_id, _killmail_id), do: {:error, :not_implemented}

  @doc "Placeholder for alliance killmails - not implemented in specialized cache"
  def get_alliance_killmails(_alliance_id), do: {:error, :not_implemented}

  @doc "Placeholder for alliance killmails - not implemented in specialized cache"
  def add_alliance_killmail(_alliance_id, _killmail_id), do: {:error, :not_implemented}

  @doc """
  Clears killmails cache.
  """
  @spec clear_killmails() :: :ok | {:error, term()}
  def clear_killmails(), do: KillmailCache.clear()

  # ===== SYSTEM CACHE OPERATIONS =====

  @doc """
  Gets active systems from the cache.
  """
  @spec get_active_systems() :: {:ok, [system_id()]} | {:error, term()}
  def get_active_systems(), do: SystemCache.get_active_systems()

  @doc """
  Adds a system to the active systems list.
  """
  @spec add_active_system(system_id()) :: :ok | {:error, term()}
  def add_active_system(system_id), do: SystemCache.add_active_system(system_id)

  @doc """
  Removes a system from the active systems list.
  """
  @spec remove_active_system(system_id()) :: :ok | {:error, term()}
  def remove_active_system(system_id), do: SystemCache.remove_active_system(system_id)

  @doc "Placeholder - not implemented in specialized cache"
  def set_active_systems(_system_ids), do: {:error, :not_implemented}

  @doc """
  Checks if a system was recently fetched.
  """
  @spec system_recently_fetched?(system_id()) :: {:ok, boolean()} | {:error, term()}
  def system_recently_fetched?(system_id), do: SystemCache.recently_fetched?(system_id)

  @doc """
  Sets the timestamp when a system was last fetched.
  """
  @spec set_system_fetch_timestamp(system_id()) :: :ok | {:error, term()}
  def set_system_fetch_timestamp(system_id), do: SystemCache.set_fetch_timestamp(system_id)

  @doc "Placeholder - not implemented in specialized cache"
  def set_system_fetch_timestamp(_system_id, _timestamp), do: {:error, :not_implemented}

  @doc """
  Gets system data from the cache.
  """
  @spec get_system_data(system_id()) :: {:ok, system_data()} | {:error, term()}
  def get_system_data(system_id), do: SystemCache.get_system_data(system_id)

  @doc """
  Caches system data.
  """
  @spec set_system_data(system_id(), system_data()) :: :ok | {:error, term()}
  def set_system_data(system_id, data), do: SystemCache.cache_system_data(system_id, data)

  @doc "Placeholder - not implemented in specialized cache"
  def get_system_fetch_timestamp(_system_id), do: {:error, :not_implemented}

  @doc """
  Gets the kill count for a system.
  """
  @spec get_system_kill_count(system_id()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_system_kill_count(system_id), do: SystemCache.get_kill_count(system_id)

  @doc """
  Increments the kill count for a system.
  """
  @spec increment_system_kill_count(system_id()) :: :ok | {:error, term()}
  def increment_system_kill_count(system_id), do: SystemCache.increment_kill_count(system_id)

  @doc "Placeholder - not implemented in specialized cache"
  def get_system_ttl(_system_id), do: {:error, :not_implemented}

  @doc "Placeholder - not implemented in specialized cache"
  def set_system_ttl(_system_id, _ttl), do: {:error, :not_implemented}

  # ===== ESI CACHE OPERATIONS =====

  @doc """
  Gets character information from ESI cache.
  """
  @spec get_character_info(character_id()) :: cache_result()
  def get_character_info(character_id), do: EsiCache.get_character_info(character_id)

  @doc """
  Gets corporation information from ESI cache.
  """
  @spec get_corporation_info(corporation_id()) :: cache_result()
  def get_corporation_info(corporation_id), do: EsiCache.get_corporation_info(corporation_id)

  @doc """
  Gets alliance information from ESI cache.
  """
  @spec get_alliance_info(alliance_id()) :: cache_result()
  def get_alliance_info(alliance_id), do: EsiCache.get_alliance_info(alliance_id)

  @doc """
  Gets type information from ESI cache.
  """
  @spec get_type_info(type_id()) :: cache_result()
  def get_type_info(type_id), do: EsiCache.get_type_info(type_id)

  @doc """
  Gets group information from ESI cache.
  """
  @spec get_group_info(pos_integer()) :: cache_result()
  def get_group_info(group_id), do: EsiCache.get_group_info(group_id)

  @doc """
  Gets system information from ESI cache.
  """
  @spec get_system_info(system_id()) :: cache_result()
  def get_system_info(system_id), do: EsiCache.get_system_info(system_id)

  @doc """
  Gets all type IDs from ESI cache.
  """
  @spec get_all_types() :: cache_result()
  def get_all_types(), do: EsiCache.get_all_types()

  @doc """
  Gets a killmail from ESI API.
  """
  @spec get_esi_killmail(killmail_id(), String.t()) :: cache_result()
  def get_esi_killmail(killmail_id, hash), do: EsiCache.get_killmail(killmail_id, hash)

  # ===== CACHE MANAGEMENT OPERATIONS =====

  @doc """
  Clears all cache data.
  """
  @spec clear_all() :: :ok
  def clear_all do
    KillmailCache.clear()
    EsiCache.clear()
    # SystemCache doesn't have a clear function, but we could implement it
    Logger.info("All caches cleared")
    :ok
  end

  @doc """
  Clears cache data for a specific cache type.
  """
  @spec clear_cache(cache_type()) :: :ok | {:error, term()}
  def clear_cache(:killmails), do: KillmailCache.clear()
  def clear_cache(:esi), do: EsiCache.clear()
  def clear_cache(:system), do: {:error, :not_implemented}
  def clear_cache(_), do: {:error, :unknown_cache_type}

  # ===== BACKWARDS COMPATIBILITY =====

  # These functions maintain backwards compatibility with existing code
  # that directly calls Cache functions without going through specialized modules

  @doc false
  @deprecated "Use get_killmail/1 instead"
  def killmail(killmail_id), do: get_killmail(killmail_id)

  @doc false
  @deprecated "Use get_active_systems/0 instead"
  def active_systems(), do: get_active_systems()

  @doc false
  @deprecated "Use get_system_data/1 instead"
  def system_data(system_id), do: get_system_data(system_id)

  # ===== UTILITY FUNCTIONS =====

  @doc """
  Checks if the cache system is healthy.
  """
  @spec health_check() :: map()
  def health_check do
    # Delegate to the new health check system
    WandererKills.Infrastructure.Health.check_health(components: [:cache])
  end

  @doc """
  Gets cache metrics and statistics.
  """
  @spec get_metrics() :: map()
  def get_metrics do
    # Delegate to the new health check system
    WandererKills.Infrastructure.Health.get_metrics(components: [:cache])
  end
end
