defmodule WandererKills.Core.Cache do
  @moduledoc """
  Simplified cache operations with a single, consistent API.

  This module provides a unified interface for all cache operations,
  eliminating duplicate methods and providing clear, consistent patterns.

  ## Usage

  All cache operations follow the same pattern:
  - `get(namespace, id)` - Get a value
  - `put(namespace, id, value)` - Store a value
  - `delete(namespace, id)` - Delete a value
  - `exists?(namespace, id)` - Check if key exists

  ## Namespaces

  - `:killmails` - Killmail data
  - `:systems` - System-related data (killmails, timestamps, active list)
  - `:characters` - Character information
  - `:corporations` - Corporation information
  - `:alliances` - Alliance information
  - `:ship_types` - Ship type data
  """

  require Logger
  alias WandererKills.Core.Support.Error

  @cache_name :wanderer_cache
  @cache_adapter Application.compile_env(:wanderer_kills, :cache_adapter, Cachex)

  # Runtime function to get cache adapter
  defp cache_adapter do
    @cache_adapter
  end

  # Namespace configurations with TTLs
  @namespace_config %{
    killmails: %{ttl: :timer.minutes(5), prefix: "killmails"},
    systems: %{ttl: :timer.hours(1), prefix: "systems"},
    characters: %{ttl: :timer.hours(24), prefix: "esi:characters"},
    corporations: %{ttl: :timer.hours(24), prefix: "esi:corporations"},
    alliances: %{ttl: :timer.hours(24), prefix: "esi:alliances"},
    ship_types: %{ttl: :timer.hours(24), prefix: "esi:ship_types"},
    groups: %{ttl: :timer.hours(24), prefix: "esi:groups"},
    character_extraction: %{ttl: :timer.minutes(5), prefix: "character_extraction"}
  }

  @type namespace ::
          :killmails
          | :systems
          | :characters
          | :corporations
          | :alliances
          | :ship_types
          | :groups
          | :character_extraction
  @type id :: String.t() | integer()
  @type value :: any()
  @type error :: {:error, Error.t()}

  # ============================================================================
  # Core Operations
  # ============================================================================

  @doc """
  Get a value from cache.

  Returns `{:ok, value}` if found, `{:error, %Error{}}` if not found.
  """
  @spec get(namespace(), id()) :: {:ok, value()} | error()
  def get(namespace, id) when is_atom(namespace) do
    key = build_key(namespace, id)

    case cache_adapter().get(@cache_name, key) do
      {:ok, nil} ->
        {:error, Error.cache_error(:not_found, "Key not found", %{namespace: namespace, id: id})}

      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("Cache get failed", namespace: namespace, id: id, error: reason)
        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @doc """
  Store a value in cache with namespace-specific TTL.
  """
  @spec put(namespace(), id(), value()) :: {:ok, boolean()} | error()
  def put(namespace, id, value) when is_atom(namespace) do
    key = build_key(namespace, id)
    ttl = get_ttl(namespace)

    case cache_adapter().put(@cache_name, key, value, ttl: ttl) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        Logger.error("Cache put failed", namespace: namespace, id: id, error: reason)
        {:error, Error.cache_error(:put_failed, "Failed to put to cache", %{reason: reason})}
    end
  end

  @doc """
  Delete a value from cache.
  """
  @spec delete(namespace(), id()) :: {:ok, boolean()} | error()
  def delete(namespace, id) when is_atom(namespace) do
    key = build_key(namespace, id)

    case cache_adapter().del(@cache_name, key) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        Logger.error("Cache delete failed", namespace: namespace, id: id, error: reason)

        {:error,
         Error.cache_error(:delete_failed, "Failed to delete from cache", %{reason: reason})}
    end
  end

  @doc """
  Check if a key exists in cache.
  """
  @spec exists?(namespace(), id()) :: boolean()
  def exists?(namespace, id) when is_atom(namespace) do
    key = build_key(namespace, id)

    case cache_adapter().exists?(@cache_name, key) do
      {:ok, exists} -> exists
      _ -> false
    end
  end

  @doc """
  Get a value or set it if not found.
  """
  @spec get_or_set(namespace(), id(), (-> value())) :: {:ok, value()} | error()
  def get_or_set(namespace, id, value_fn) when is_atom(namespace) and is_function(value_fn, 0) do
    case get(namespace, id) do
      {:ok, value} ->
        {:ok, value}

      {:error, %Error{type: :not_found}} ->
        value = value_fn.()
        put(namespace, id, value)
        {:ok, value}

      error ->
        error
    end
  end

  # ============================================================================
  # System-Specific Operations
  # ============================================================================

  @doc """
  List killmail IDs for a system.
  """
  @spec list_system_killmails(integer()) :: {:ok, [integer()]} | {:ok, any()} | error()
  def list_system_killmails(system_id) do
    get(:systems, "killmails:#{system_id}")
  end

  @doc """
  Add a killmail ID to a system's list.
  """
  @spec add_system_killmail(integer(), integer()) :: {:ok, boolean()} | error()
  def add_system_killmail(system_id, killmail_id) do
    case list_system_killmails(system_id) do
      {:ok, existing_ids} when is_list(existing_ids) ->
        if killmail_id in existing_ids do
          {:ok, true}
        else
          put(:systems, "killmails:#{system_id}", [killmail_id | existing_ids])
        end

      {:error, %Error{type: :not_found}} ->
        put(:systems, "killmails:#{system_id}", [killmail_id])

      {:ok, _invalid_data} ->
        # Handle corrupted data by starting fresh
        Logger.warning("Corrupted system killmail data found, resetting", system_id: system_id)
        put(:systems, "killmails:#{system_id}", [killmail_id])

      error ->
        error
    end
  end

  @doc """
  Mark a system as having been fetched.
  """
  @spec mark_system_fetched(integer(), DateTime.t()) :: {:ok, boolean()} | error()
  def mark_system_fetched(system_id, timestamp \\ DateTime.utc_now()) do
    put(:systems, "last_fetch:#{system_id}", timestamp)
  end

  @doc """
  Check if a system was fetched within the given time window.
  """
  @spec system_fetched_recently?(integer(), integer()) :: boolean()
  def system_fetched_recently?(system_id, within_seconds \\ 3600) do
    case get(:systems, "last_fetch:#{system_id}") do
      {:ok, last_fetch} when is_struct(last_fetch, DateTime) ->
        DateTime.diff(DateTime.utc_now(), last_fetch) <= within_seconds

      _ ->
        false
    end
  end

  @doc """
  Get list of active systems.
  """
  @spec get_active_systems() :: {:ok, [integer()]} | error()
  def get_active_systems do
    case get(:systems, "active_list") do
      {:ok, systems} -> {:ok, systems}
      {:error, %Error{type: :not_found}} -> {:ok, []}
      error -> error
    end
  end

  @doc """
  Add a system to the active list.
  """
  @spec add_active_system(integer()) :: {:ok, boolean()} | error()
  def add_active_system(system_id) do
    case get_active_systems() do
      {:ok, systems} ->
        if system_id in systems do
          {:ok, true}
        else
          put(:systems, "active_list", [system_id | systems])
        end

      error ->
        error
    end
  end

  # ============================================================================
  # Monitoring & Statistics Operations
  # ============================================================================

  @doc """
  Get cache size (total number of entries).
  """
  @spec size() :: {:ok, non_neg_integer()} | error()
  def size do
    case cache_adapter().size(@cache_name) do
      {:ok, size} -> {:ok, size}
      {:error, reason} ->
        Logger.error("Cache size check failed", error: reason)
        {:error, Error.cache_error(:size_failed, "Failed to get cache size", %{reason: reason})}
    end
  end

  @doc """
  Get cache statistics including hit/miss rates.
  """
  @spec stats() :: {:ok, map()} | error()
  def stats do
    adapter = cache_adapter()
    
    if to_string(adapter) == "Elixir.Cachex" do
      case adapter.stats(@cache_name) do
        {:ok, stats} -> {:ok, stats}
        {:error, reason} ->
          Logger.error("Cache stats retrieval failed", error: reason)
          {:error, Error.cache_error(:stats_failed, "Failed to get cache stats", %{reason: reason})}
      end
    else
      # For ETS adapter and others, provide basic stats
      case size() do
        {:ok, size_val} -> {:ok, %{hits: 0, misses: 0, size: size_val, hit_rate: 0.0, miss_rate: 0.0}}
        error -> error
      end
    end
  end

  @doc """
  Get all keys for a specific namespace.
  Useful for namespace clearing and debugging.
  """
  @spec keys(namespace()) :: {:ok, [String.t()]} | error()
  def keys(namespace) when is_atom(namespace) do
    config = @namespace_config[namespace]
    prefix = config.prefix
    adapter = cache_adapter()
    
    if to_string(adapter) == "Elixir.Cachex" do
      case adapter.keys(@cache_name) do
        {:ok, all_keys} -> 
          namespace_keys = Enum.filter(all_keys, &String.starts_with?(&1, "#{prefix}:"))
          {:ok, namespace_keys}
        {:error, reason} ->
          Logger.error("Cache keys retrieval failed", namespace: namespace, error: reason)
          {:error, Error.cache_error(:keys_failed, "Failed to get cache keys", %{reason: reason})}
      end
    else
      # For ETS adapter and others, return empty list (not implemented)
      {:ok, []}
    end
  end

  @doc """
  Clear all entries for a specific namespace.
  """
  @spec clear_namespace(namespace()) :: {:ok, integer()} | error()
  def clear_namespace(namespace) when is_atom(namespace) do
    case keys(namespace) do
      {:ok, keys} ->
        results = Enum.map(keys, &cache_adapter().del(@cache_name, &1))
        success_count = Enum.count(results, fn 
          {:ok, _} -> true
          _ -> false 
        end)
        {:ok, success_count}

      error -> error
    end
  end

  @doc """
  Get detailed cache health information including size and statistics.
  """
  @spec health() :: {:ok, map()} | error()
  def health do
    with {:ok, size} <- size(),
         {:ok, stats} <- stats() do
      health_info = %{
        name: @cache_name,
        healthy: true,
        status: "ok",
        size: size,
        hit_rate: Map.get(stats, :hit_rate, 0.0),
        miss_rate: Map.get(stats, :miss_rate, 0.0),
        hits: Map.get(stats, :hits, 0),
        misses: Map.get(stats, :misses, 0)
      }
      {:ok, health_info}
    else
      {:error, _} -> 
        health_info = %{
          name: @cache_name,
          healthy: false,
          status: "error",
          size: 0
        }
        {:ok, health_info}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_key(namespace, id) do
    config = @namespace_config[namespace]
    "#{config.prefix}:#{to_string(id)}"
  end

  defp get_ttl(namespace) do
    @namespace_config[namespace].ttl
  end
end
