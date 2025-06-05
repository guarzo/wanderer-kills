defmodule WandererKills.Cache do
  @moduledoc """
  Simplified cache interface for WandererKills.

  This module provides a clean, direct interface to the unified Cachex instance,
  replacing the complex hierarchy of Base → Unified → Specialized caches with
  a single, straightforward API.

  ## Features

  - Direct Cachex operations with namespaced keys
  - Consistent error handling and return patterns
  - Type-safe operations with proper specs
  - Simplified architecture without unnecessary abstractions

  ## Usage

  ```elixir
  # Killmail operations
  {:ok, killmail} = Cache.get_killmail(123)
  :ok = Cache.set_killmail(123, killmail_data)

  # System operations
  {:ok, systems} = Cache.get_active_systems()
  :ok = Cache.add_active_system(30000142)

  # ESI operations
  {:ok, character} = Cache.get_character_info(123456)
  :ok = Cache.set_type_info(456, type_data)
  ```

  ## Key Namespacing

  All cache keys are namespaced to avoid conflicts:
  - `killmails:*` - Killmail data
  - `systems:*` - System-specific data
  - `esi:*` - ESI API responses
  """

  require Logger
  alias WandererKills.{Config, Constants}

  @cache_name :unified_cache

  # Type definitions
  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type character_id :: pos_integer()
  @type corporation_id :: pos_integer()
  @type alliance_id :: pos_integer()
  @type type_id :: pos_integer()
  @type cache_result(t) :: {:ok, t} | {:error, term()}

  # =============================================================================
  # Killmail Cache Operations
  # =============================================================================

  @doc """
  Gets a killmail by ID from the cache.
  """
  @spec get_killmail(killmail_id()) :: cache_result(map())
  def get_killmail(killmail_id) do
    key = "killmails:#{killmail_id}"

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets a killmail in the cache.
  """
  @spec set_killmail(killmail_id(), map()) :: :ok | {:error, term()}
  def set_killmail(killmail_id, killmail) do
    key = "killmails:#{killmail_id}"
    ttl = Config.cache_ttl(:killmails)

    case Cachex.put(@cache_name, key, killmail, ttl: ttl) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a killmail by ID from the cache.
  """
  @spec delete_killmail(killmail_id()) :: :ok | {:error, term()}
  def delete_killmail(killmail_id) do
    key = "killmails:#{killmail_id}"

    case Cachex.del(@cache_name, key) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets all killmail IDs from the cache.
  """
  @spec get_killmail_ids() :: cache_result([killmail_id()])
  def get_killmail_ids() do
    key = "killmails:ids"

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:ok, []}
      {:ok, ids} when is_list(ids) -> {:ok, ids}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Adds a killmail ID to the tracked list.
  """
  @spec add_killmail_id(killmail_id()) :: :ok | {:error, term()}
  def add_killmail_id(killmail_id) do
    key = "killmails:ids"
    ttl = Config.cache_ttl(:killmails)

    case get_killmail_ids() do
      {:ok, ids} ->
        new_ids = [killmail_id | ids] |> Enum.uniq()

        case Cachex.put(@cache_name, key, new_ids, ttl: ttl) do
          {:ok, true} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # =============================================================================
  # System Cache Operations
  # =============================================================================

  @doc """
  Gets active systems from the cache.
  """
  @spec get_active_systems() :: cache_result([system_id()])
  def get_active_systems() do
    key = "systems:active"

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:ok, []}
      {:ok, systems} when is_list(systems) -> {:ok, systems}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Adds a system to the active systems list.
  """
  @spec add_active_system(system_id()) :: :ok | {:error, term()}
  def add_active_system(system_id) do
    key = "systems:active"
    ttl = Config.cache_ttl(:system)

    case get_active_systems() do
      {:ok, systems} ->
        new_systems = [system_id | systems] |> Enum.uniq()

        case Cachex.put(@cache_name, key, new_systems, ttl: ttl) do
          {:ok, true} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets killmail IDs for a specific system.
  """
  @spec get_system_killmails(system_id()) :: cache_result([killmail_id()])
  def get_system_killmails(system_id) do
    key = "systems:#{system_id}:killmails"

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:ok, []}
      {:ok, killmail_ids} when is_list(killmail_ids) -> {:ok, killmail_ids}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Adds a killmail to a system's killmail list.
  """
  @spec add_system_killmail(system_id(), killmail_id()) :: :ok | {:error, term()}
  def add_system_killmail(system_id, killmail_id) do
    key = "systems:#{system_id}:killmails"
    ttl = Config.cache_ttl(:system)

    case get_system_killmails(system_id) do
      {:ok, killmail_ids} ->
        new_ids = [killmail_id | killmail_ids] |> Enum.uniq()

        case Cachex.put(@cache_name, key, new_ids, ttl: ttl) do
          {:ok, true} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a system was recently fetched.
  """
  @spec system_recently_fetched?(system_id()) :: cache_result(boolean())
  def system_recently_fetched?(system_id) do
    key = "systems:#{system_id}:fetch_timestamp"
    threshold = Constants.threshold(:recent_fetch)

    case Cachex.get(@cache_name, key) do
      {:ok, nil} ->
        {:ok, false}

      {:ok, timestamp} when is_struct(timestamp, DateTime) ->
        seconds_ago = DateTime.diff(DateTime.utc_now(), timestamp)
        {:ok, seconds_ago < threshold}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sets the fetch timestamp for a system.
  """
  @spec set_system_fetch_timestamp(system_id()) :: :ok | {:error, term()}
  def set_system_fetch_timestamp(system_id) do
    set_system_fetch_timestamp(system_id, DateTime.utc_now())
  end

  @doc """
  Sets the fetch timestamp for a system to a specific time.
  """
  @spec set_system_fetch_timestamp(system_id(), DateTime.t()) :: :ok | {:error, term()}
  def set_system_fetch_timestamp(system_id, timestamp) do
    key = "systems:#{system_id}:fetch_timestamp"
    ttl = Config.cache_ttl(:system)

    case Cachex.put(@cache_name, key, timestamp, ttl: ttl) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # ESI Cache Operations
  # =============================================================================

  @doc """
  Gets character information from the cache.
  """
  @spec get_character_info(character_id()) :: cache_result(map())
  def get_character_info(character_id) do
    key = "esi:character:#{character_id}"

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets character information in the cache.
  """
  @spec set_character_info(character_id(), map()) :: :ok | {:error, term()}
  def set_character_info(character_id, character_info) do
    key = "esi:character:#{character_id}"
    ttl = Config.cache_ttl(:esi)

    case Cachex.put(@cache_name, key, character_info, ttl: ttl) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets corporation information from the cache.
  """
  @spec get_corporation_info(corporation_id()) :: cache_result(map())
  def get_corporation_info(corporation_id) do
    key = "esi:corporation:#{corporation_id}"

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets corporation information in the cache.
  """
  @spec set_corporation_info(corporation_id(), map()) :: :ok | {:error, term()}
  def set_corporation_info(corporation_id, corp_info) do
    key = "esi:corporation:#{corporation_id}"
    ttl = Config.cache_ttl(:esi)

    case Cachex.put(@cache_name, key, corp_info, ttl: ttl) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets alliance information from the cache.
  """
  @spec get_alliance_info(alliance_id()) :: cache_result(map())
  def get_alliance_info(alliance_id) do
    key = "esi:alliance:#{alliance_id}"

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets alliance information in the cache.
  """
  @spec set_alliance_info(alliance_id(), map()) :: :ok | {:error, term()}
  def set_alliance_info(alliance_id, alliance_info) do
    key = "esi:alliance:#{alliance_id}"
    ttl = Config.cache_ttl(:esi)

    case Cachex.put(@cache_name, key, alliance_info, ttl: ttl) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets type information from the cache.
  """
  @spec get_type_info(type_id()) :: cache_result(map())
  def get_type_info(type_id) do
    key = "esi:type:#{type_id}"

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets type information in the cache.
  """
  @spec set_type_info(type_id(), map()) :: :ok | {:error, term()}
  def set_type_info(type_id, type_info) do
    key = "esi:type:#{type_id}"
    ttl = Config.cache_ttl(:esi)

    case Cachex.put(@cache_name, key, type_info, ttl: ttl) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets group information from the cache.
  """
  @spec get_group_info(pos_integer()) :: cache_result(map())
  def get_group_info(group_id) do
    key = "esi:group:#{group_id}"

    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets group information in the cache.
  """
  @spec set_group_info(pos_integer(), map()) :: :ok | {:error, term()}
  def set_group_info(group_id, group_info) do
    key = "esi:group:#{group_id}"
    ttl = Config.cache_ttl(:esi)

    case Cachex.put(@cache_name, key, group_info, ttl: ttl) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # Utility Functions
  # =============================================================================

  @doc """
  Clears all cache entries for a specific namespace.
  """
  @spec clear_namespace(String.t()) :: :ok | {:error, term()}
  def clear_namespace(namespace) do
    pattern = "#{namespace}:*"

    case Cachex.keys(@cache_name, pattern) do
      {:ok, keys} ->
        case Cachex.del(@cache_name, keys) do
          {:ok, _count} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets cache statistics.
  """
  @spec stats() :: cache_result(map())
  def stats() do
    case Cachex.stats(@cache_name) do
      {:ok, stats} -> {:ok, stats}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks if the cache is healthy.
  """
  @spec healthy?() :: boolean()
  def healthy?() do
    case Cachex.size(@cache_name) do
      {:ok, _size} -> true
      {:error, _} -> false
    end
  end
end
