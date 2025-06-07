defmodule WandererKills.Cache do
  @moduledoc """
  Unified cache interface for WandererKills.

  This module provides a single API for caching that internally uses:
  - Cachex for TTL-based general caching (unified_cache)
  - ETS for high-performance data storage (via Core.Cache)

  This implements the ETS to Cachex migration strategy.
  """

  # Import cache-related modules
  alias WandererKills.Core.Cache, as: CoreCache

  @cache_name :unified_cache

  #
  # Basic Cache Operations
  #

  @doc """
  Gets a value from the cache using namespaced keys.
  """
  @spec get(term()) :: {:ok, term()} | {:error, :not_found}
  def get(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:error, :not_found}
    end
  end

  @doc """
  Sets a value in the cache with optional TTL.
  """
  @spec set(term(), term(), keyword()) :: :ok | {:error, term()}
  def set(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl)

    case Cachex.put(@cache_name, key, value, ttl: ttl) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a value from the cache.
  """
  @spec del(term()) :: :ok
  def del(key) do
    Cachex.del(@cache_name, key)
    :ok
  end

  #
  # Killmail Operations
  #

  @doc """
  Stores a killmail in the cache.
  """
  @spec set_killmail(integer(), map()) :: :ok
  def set_killmail(killmail_id, killmail_data) do
    key = "killmail:#{killmail_id}"
    set(key, killmail_data)
  end

  @doc """
  Retrieves a killmail from the cache.
  """
  @spec get_killmail(integer()) :: {:ok, map()} | {:error, :not_found}
  def get_killmail(killmail_id) do
    key = "killmail:#{killmail_id}"
    get(key)
  end

  @doc """
  Deletes a killmail from the cache.
  """
  @spec delete_killmail(integer()) :: :ok
  def delete_killmail(killmail_id) do
    key = "killmail:#{killmail_id}"
    del(key)
  end

  #
  # System Operations
  #

  @doc """
  Adds a killmail to a system's killmail list.
  """
  @spec add_system_killmail(integer(), integer()) :: :ok
  def add_system_killmail(system_id, killmail_id) do
    CoreCache.add_system_killmail(system_id, killmail_id)
  end

  @doc """
  Gets all killmails for a system.
  """
  @spec get_killmails_for_system(integer()) :: {:ok, [integer()]} | {:error, :not_found}
  def get_killmails_for_system(system_id) do
    case CoreCache.get_killmails_for_system(system_id) do
      {:ok, killmail_ids} -> {:ok, killmail_ids}
      {:error, _} -> {:ok, []}
    end
  end

  @doc """
  Gets killmails for a system (alias for backward compatibility).
  """
  @spec get_system_killmails(integer()) :: {:ok, [integer()]} | {:error, :not_found}
  def get_system_killmails(system_id) do
    get_killmails_for_system(system_id)
  end

  @doc """
  Gets active systems.
  """
  @spec get_active_systems() :: {:ok, [integer()]}
  def get_active_systems() do
    case CoreCache.get_active_systems() do
      {:ok, systems} -> {:ok, systems}
      {:error, _} -> {:ok, []}
    end
  end

  @doc """
  Adds a system to the active systems list.
  """
  @spec add_active_system(integer()) :: {:ok, :added}
  def add_active_system(system_id) do
    case CoreCache.add_active_system(system_id) do
      :ok -> {:ok, :added}
      other -> other
    end
  end

  #
  # Kill Count Operations
  #

  @doc """
  Increments the kill count for a system.
  """
  @spec increment_system_kill_count(integer()) :: {:ok, integer()}
  def increment_system_kill_count(system_id) do
    CoreCache.increment_system_kill_count(system_id)
  end

  @doc """
  Gets the kill count for a system.
  """
  @spec get_system_kill_count(integer()) :: {:ok, integer()}
  def get_system_kill_count(system_id) do
    case CoreCache.get_system_kill_count(system_id) do
      {:ok, count} -> {:ok, count}
      {:error, _} -> {:ok, 0}
    end
  end

  #
  # Fetch Timestamp Operations
  #

  @doc """
  Sets the fetch timestamp for a system.
  """
  @spec set_system_fetch_timestamp(integer(), DateTime.t()) :: {:ok, :set}
  def set_system_fetch_timestamp(system_id, timestamp) do
    case CoreCache.set_system_fetch_timestamp(system_id, timestamp) do
      :ok -> {:ok, :set}
      other -> other
    end
  end

  @doc """
  Checks if a system was recently fetched.
  """
  @spec system_recently_fetched?(integer()) :: {:ok, boolean()}
  def system_recently_fetched?(system_id) do
    CoreCache.system_recently_fetched?(system_id)
  end

  #
  # ESI Cache Operations
  #

  @doc """
  Sets character information in the cache.
  """
  @spec set_character_info(integer(), map()) :: :ok
  def set_character_info(character_id, character_data) do
    key = "esi:character:#{character_id}"
    set(key, character_data, ttl: :timer.hours(24))
  end

  @doc """
  Gets character information from the cache.
  """
  @spec get_character_info(integer()) :: {:ok, map()} | {:error, :not_found}
  def get_character_info(character_id) do
    key = "esi:character:#{character_id}"
    get(key)
  end

  @doc """
  Sets corporation information in the cache.
  """
  @spec set_corporation_info(integer(), map()) :: :ok
  def set_corporation_info(corporation_id, corporation_data) do
    key = "esi:corporation:#{corporation_id}"
    set(key, corporation_data, ttl: :timer.hours(24))
  end

  @doc """
  Gets corporation information from the cache.
  """
  @spec get_corporation_info(integer()) :: {:ok, map()} | {:error, :not_found}
  def get_corporation_info(corporation_id) do
    key = "esi:corporation:#{corporation_id}"
    get(key)
  end

  @doc """
  Sets alliance information in the cache.
  """
  @spec set_alliance_info(integer(), map()) :: :ok
  def set_alliance_info(alliance_id, alliance_data) do
    key = "esi:alliance:#{alliance_id}"
    set(key, alliance_data, ttl: :timer.hours(24))
  end

  @doc """
  Gets alliance information from the cache.
  """
  @spec get_alliance_info(integer()) :: {:ok, map()} | {:error, :not_found}
  def get_alliance_info(alliance_id) do
    key = "esi:alliance:#{alliance_id}"
    get(key)
  end

  @doc """
  Sets type information in the cache.
  """
  @spec set_type_info(integer(), map()) :: :ok
  def set_type_info(type_id, type_data) do
    key = "esi:type:#{type_id}"
    set(key, type_data, ttl: :timer.hours(24))
  end

  @doc """
  Gets type information from the cache.
  """
  @spec get_type_info(integer()) :: {:ok, map()} | {:error, :not_found}
  def get_type_info(type_id) do
    key = "esi:type:#{type_id}"
    get(key)
  end

  @doc """
  Sets group information in the cache.
  """
  @spec set_group_info(integer(), map()) :: :ok
  def set_group_info(group_id, group_data) do
    key = "esi:group:#{group_id}"
    set(key, group_data, ttl: :timer.hours(24))
  end

  @doc """
  Gets group information from the cache.
  """
  @spec get_group_info(integer()) :: {:ok, map()} | {:error, :not_found}
  def get_group_info(group_id) do
    key = "esi:group:#{group_id}"
    get(key)
  end

  #
  # Namespace Operations
  #

  @doc """
  Clears all entries in a namespace.
  """
  @spec clear_namespace(String.t()) :: :ok
  def clear_namespace(namespace) do
    # For Cachex, we need to get all keys with the namespace prefix and delete them
    pattern = "#{namespace}:*"

    case Cachex.stream(@cache_name, pattern) do
      {:ok, stream} ->
        stream
        |> Enum.each(fn {key, _value} -> Cachex.del(@cache_name, key) end)

      {:error, _} ->
        :ok
    end

    :ok
  end

  #
  # Health and Stats
  #

  @doc """
  Checks if the cache is healthy.
  """
  @spec healthy?() :: boolean()
  def healthy?() do
    # Try a simple operation to check if cache is working
    case Cachex.put(@cache_name, "health_check", true, ttl: 1000) do
      {:ok, true} -> true
      _ -> false
    end
  end

  @doc """
  Gets cache statistics.
  """
  @spec stats() :: {:ok, map()} | {:error, :disabled}
  def stats() do
    case Cachex.stats(@cache_name) do
      {:ok, stats} -> {:ok, stats}
      {:error, _} -> {:error, :disabled}
    end
  end
end
