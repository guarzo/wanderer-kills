defmodule WandererKills.Cache.Unified do
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
  {:ok, killmail} = Cache.Unified.get_killmail(123)
  :ok = Cache.Unified.set_killmail(123, killmail_data)

  # System operations
  {:ok, system_ids} = Cache.Unified.get_active_systems()
  :ok = Cache.Unified.increment_system_kill_count(30000142)

  # ESI operations
  {:ok, character} = Cache.Unified.get_character_info(123456)
  {:ok, type_info} = Cache.Unified.get_type_info(456)
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
  alias WandererKills.Cache.Base

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
  @type cache_status :: :ok | {:error, term()}

  # ===== KILLMAIL CACHE OPERATIONS =====

  @doc """
  Gets a killmail by ID from the cache.
  """
  @spec get_killmail(killmail_id()) :: {:ok, killmail()} | {:error, term()}
  def get_killmail(killmail_id), do: KillmailCache.get_killmail(killmail_id)

  @doc """
  Sets a killmail in the cache.
  """
  @spec set_killmail(killmail_id(), killmail()) :: {:ok, boolean()} | {:error, term()}
  def set_killmail(killmail_id, killmail) do
    case KillmailCache.set_killmail(killmail_id, killmail) do
      :ok -> {:ok, true}
      error -> error
    end
  end

  @doc """
  Deletes a killmail by ID from the cache.
  """
  @spec delete_killmail(killmail_id()) :: {:ok, boolean()} | {:error, term()}
  def delete_killmail(killmail_id) do
    case KillmailCache.delete_killmail(killmail_id) do
      :ok -> {:ok, true}
      error -> error
    end
  end

  @doc """
  Gets all killmail IDs from the cache.
  """
  @spec get_killmail_ids() :: cache_result()
  def get_killmail_ids(), do: KillmailCache.get_killmail_ids()

  @doc """
  Adds a killmail ID to the killmail list.
  """
  @spec add_killmail_id(killmail_id()) :: cache_status()
  def add_killmail_id(killmail_id), do: KillmailCache.add_killmail_id(killmail_id)

  @doc """
  Removes a killmail ID from the killmail list.
  """
  @spec remove_killmail_id(killmail_id()) :: cache_status()
  def remove_killmail_id(killmail_id), do: KillmailCache.remove_killmail_id(killmail_id)

  # ===== SYSTEM CACHE OPERATIONS =====

  @doc """
  Gets all killmails for a system.
  """
  @spec get_killmails_for_system(system_id()) :: cache_result()
  def get_killmails_for_system(system_id), do: SystemCache.get_killmails_for_system(system_id)

  @doc """
  Gets all killmail IDs for a system.
  """
  @spec get_killmail_ids_for_system(system_id()) :: cache_result()
  def get_killmail_ids_for_system(system_id),
    do: SystemCache.get_killmail_ids_for_system(system_id)

  @doc """
  Adds a killmail to a system's killmail list.
  """
  @spec add_system_killmail(system_id(), killmail_id()) :: {:ok, boolean()} | {:error, term()}
  def add_system_killmail(system_id, killmail_id) do
    case SystemCache.add_system_killmail(system_id, killmail_id) do
      :ok -> {:ok, true}
      error -> error
    end
  end

  @doc """
  Removes a killmail from a system's killmail list.
  """
  @spec remove_system_killmail(system_id(), killmail_id()) :: {:ok, boolean()} | {:error, term()}
  def remove_system_killmail(system_id, killmail_id) do
    case SystemCache.remove_system_killmail(system_id, killmail_id) do
      :ok -> {:ok, true}
      error -> error
    end
  end

  @doc """
  Gets active systems from the cache.
  """
  @spec get_active_systems() :: cache_result()
  def get_active_systems(), do: SystemCache.get_active_systems()

  @doc """
  Adds a system to the active systems list.
  """
  @spec add_active_system(system_id()) :: cache_status()
  def add_active_system(system_id), do: SystemCache.add_active_system(system_id)

  @doc """
  Checks if a system was recently fetched.
  """
  @spec system_recently_fetched?(system_id()) :: {:ok, boolean()} | {:error, term()}
  def system_recently_fetched?(system_id), do: SystemCache.recently_fetched?(system_id)

  @doc """
  Sets the timestamp for when a system was last fetched to the current time.
  """
  @spec set_system_fetch_timestamp(integer()) :: {:ok, boolean()} | {:error, term()}
  def set_system_fetch_timestamp(system_id) do
    case SystemCache.set_fetch_timestamp(system_id) do
      :ok -> {:ok, true}
      error -> error
    end
  end

  @doc """
  Sets the timestamp for when a system was last fetched to a specific time.
  """
  @spec set_system_fetch_timestamp(integer(), DateTime.t()) :: {:ok, boolean()} | {:error, term()}
  def set_system_fetch_timestamp(system_id, timestamp) do
    case SystemCache.set_fetch_timestamp(system_id, timestamp) do
      :ok -> {:ok, true}
      error -> error
    end
  end

  @doc """
  Gets the timestamp for when a system was last fetched.
  """
  @spec get_system_fetch_timestamp(integer()) :: {:ok, DateTime.t() | nil} | {:error, term()}
  def get_system_fetch_timestamp(system_id), do: SystemCache.get_fetch_timestamp(system_id)

  @doc """
  Gets system data from the cache.
  """
  @spec get_system_data(system_id()) :: cache_result()
  def get_system_data(system_id), do: SystemCache.get_system_data(system_id)

  @doc """
  Caches system data.
  """
  @spec set_system_data(system_id(), system_data()) :: cache_status()
  def set_system_data(system_id, data), do: SystemCache.cache_system_data(system_id, data)

  @doc """
  Gets the kill count for a system.
  """
  @spec get_system_kill_count(system_id()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_system_kill_count(system_id), do: SystemCache.get_system_kill_count(system_id)

  @doc """
  Increments the kill count for a system.
  """
  @spec increment_system_kill_count(system_id()) :: {:ok, boolean()} | {:error, term()}
  def increment_system_kill_count(system_id) do
    case SystemCache.increment_kill_count(system_id) do
      :ok -> {:ok, true}
      error -> error
    end
  end

  @doc """
  Decrements the kill count for a system.
  """
  @spec decrement_system_kill_count(system_id()) :: {:ok, boolean()} | {:error, term()}
  def decrement_system_kill_count(system_id) do
    case SystemCache.decrement_kill_count(system_id) do
      :ok -> {:ok, true}
      error -> error
    end
  end

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
    Base.clear(:system)
    Logger.info("All caches cleared")
    :ok
  end

  @doc """
  Clears cache data for a specific cache type.
  """
  @spec clear_cache(cache_type()) :: cache_status()
  def clear_cache(:killmails), do: KillmailCache.clear()
  def clear_cache(:esi), do: EsiCache.clear()
  def clear_cache(:system), do: Base.clear(:system)
  def clear_cache(_), do: {:error, :unknown_cache_type}

  # ===== UTILITY FUNCTIONS =====

  @doc """
  Checks if the cache system is healthy.
  """
  @spec health_check() :: map()
  def health_check do
    WandererKills.Infrastructure.HealthChecks.Runner.run_all_checks()
  end

  @doc """
  Gets cache metrics and statistics.
  """
  @spec get_metrics() :: map()
  def get_metrics do
    WandererKills.Infrastructure.HealthChecks.CacheHealth.get_metrics()
  end
end
