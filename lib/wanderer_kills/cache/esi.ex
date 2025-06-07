defmodule WandererKills.Cache.ESI do
  @moduledoc """
  Domain-specific cache wrapper for ESI data.

  **DEPRECATED**: This module is now a thin wrapper around `WandererKills.Cache.Helper`.
  Use `Helper.character_*`, `Helper.corporation_*`, `Helper.alliance_*`,
  and `Helper.killmail_*` functions directly for new code.

  This module encapsulates all Cachex operations for ESI-related data
  including characters, corporations, alliances, and killmails,
  providing a clean interface for business logic without direct
  Cachex dependencies.
  """

  alias WandererKills.Core.Error
  alias WandererKills.Cache.Helper
  require Logger

  @doc """
  Generates a cache key for ESI data.
  """
  @spec key(atom(), integer()) :: String.t()
  def key(type, id) when is_atom(type) and is_integer(id) do
    "esi:#{type}:#{id}"
  end

  @spec key(atom(), integer(), String.t()) :: String.t()
  def key(cache_name, id, prefix)
      when is_atom(cache_name) and is_integer(id) and is_binary(prefix) do
    "esi:#{prefix}:#{id}"
  end

  @doc """
  Gets character data from cache.
  """
  @spec get_character(integer()) :: {:ok, map()} | {:error, term()}
  def get_character(character_id) when is_integer(character_id) do
    case Helper.character_get(character_id) do
      {:error, :not_found} ->
        {:error, Error.cache_error(:not_found, "characters not found in cache")}

      other ->
        other
    end
  end

  @doc """
  Gets character data from cache or sets it using a fallback function.
  """
  @spec get_or_set_character(integer(), (-> map())) :: {:ok, map()} | {:error, term()}
  def get_or_set_character(character_id, fallback_fn) when is_integer(character_id) do
    Helper.character_get_or_set(character_id, fallback_fn)
  end

  @doc """
  Puts character data in cache.
  """
  @spec put_character(integer(), map()) :: :ok | {:error, term()}
  def put_character(character_id, character_data) when is_integer(character_id) do
    case Helper.character_put(character_id, character_data) do
      {:ok, true} -> :ok
      other -> other
    end
  end

  @doc """
  Gets corporation data from cache.
  """
  @spec get_corporation(integer()) :: {:ok, map()} | {:error, term()}
  def get_corporation(corporation_id) when is_integer(corporation_id) do
    case Helper.corporation_get(corporation_id) do
      {:error, :not_found} ->
        {:error, Error.cache_error(:not_found, "corporations not found in cache")}

      other ->
        other
    end
  end

  @doc """
  Gets corporation data from cache or sets it using a fallback function.
  """
  @spec get_or_set_corporation(integer(), (-> map())) :: {:ok, map()} | {:error, term()}
  def get_or_set_corporation(corporation_id, fallback_fn) when is_integer(corporation_id) do
    Helper.corporation_get_or_set(corporation_id, fallback_fn)
  end

  @doc """
  Puts corporation data in cache.
  """
  @spec put_corporation(integer(), map()) :: :ok | {:error, term()}
  def put_corporation(corporation_id, corporation_data) when is_integer(corporation_id) do
    case Helper.corporation_put(corporation_id, corporation_data) do
      {:ok, true} -> :ok
      other -> other
    end
  end

  @doc """
  Gets alliance data from cache.
  """
  @spec get_alliance(integer()) :: {:ok, map()} | {:error, term()}
  def get_alliance(alliance_id) when is_integer(alliance_id) do
    case Helper.alliance_get(alliance_id) do
      {:error, :not_found} ->
        {:error, Error.cache_error(:not_found, "alliances not found in cache")}

      other ->
        other
    end
  end

  @doc """
  Gets alliance data from cache or sets it using a fallback function.
  """
  @spec get_or_set_alliance(integer(), (-> map())) :: {:ok, map()} | {:error, term()}
  def get_or_set_alliance(alliance_id, fallback_fn) when is_integer(alliance_id) do
    Helper.alliance_get_or_set(alliance_id, fallback_fn)
  end

  @doc """
  Puts alliance data in cache.
  """
  @spec put_alliance(integer(), map()) :: :ok | {:error, term()}
  def put_alliance(alliance_id, alliance_data) when is_integer(alliance_id) do
    case Helper.alliance_put(alliance_id, alliance_data) do
      {:ok, true} -> :ok
      other -> other
    end
  end

  @doc """
  Gets killmail data from cache.
  """
  @spec get_killmail(integer()) :: {:ok, map()} | {:error, term()}
  def get_killmail(killmail_id) when is_integer(killmail_id) do
    case Helper.killmail_get(killmail_id) do
      {:error, :not_found} ->
        {:error, Error.cache_error(:not_found, "killmails not found in cache")}

      other ->
        other
    end
  end

  @doc """
  Gets killmail data from cache or sets it using a fallback function.
  """
  @spec get_or_set_killmail(integer(), (-> map())) :: {:ok, map()} | {:error, term()}
  def get_or_set_killmail(killmail_id, fallback_fn) when is_integer(killmail_id) do
    Helper.killmail_get_or_set(killmail_id, fallback_fn)
  end

  @doc """
  Puts killmail data in cache.
  """
  @spec put_killmail(integer(), map()) :: :ok | {:error, term()}
  def put_killmail(killmail_id, killmail_data) when is_integer(killmail_id) do
    case Helper.killmail_put(killmail_id, killmail_data) do
      {:ok, true} -> :ok
      other -> other
    end
  end

  @doc """
  Gets type data from cache.
  """
  @spec get_type(integer()) :: {:ok, map()} | {:error, Error.t()}
  def get_type(type_id) when is_integer(type_id) do
    # Types are stored in the ship_types cache
    WandererKills.Cache.ShipTypes.get(type_id)
  end

  @doc """
  Gets type data from cache or sets it using a fallback function.
  """
  @spec get_or_set_type(integer(), (-> map())) :: {:ok, map()} | {:error, Error.t()}
  def get_or_set_type(type_id, fallback_fn) when is_integer(type_id) do
    # Types are stored in the ship_types cache
    WandererKills.Cache.ShipTypes.get_or_set(type_id, fallback_fn)
  end

  @doc """
  Puts type data in cache.
  """
  @spec put_type(integer(), map()) :: :ok | {:error, Error.t()}
  def put_type(type_id, type_data) when is_integer(type_id) do
    # Types are stored in the ship_types cache
    WandererKills.Cache.ShipTypes.put(type_id, type_data)
  end

  @doc """
  Gets group data from cache.
  """
  @spec get_group(integer()) :: {:ok, map()} | {:error, Error.t()}
  def get_group(group_id) when is_integer(group_id) do
    case Helper.get("esi", "group:#{group_id}") do
      {:ok, nil} -> {:error, Error.cache_error(:not_found, "group not found in cache")}
      other -> other
    end
  end

  @doc """
  Gets group data from cache or sets it using a fallback function.
  """
  @spec get_or_set_group(integer(), (-> map())) :: {:ok, map()} | {:error, Error.t()}
  def get_or_set_group(group_id, fallback_fn) when is_integer(group_id) do
    Helper.get_or_set("esi", "group:#{group_id}", fallback_fn)
  end

  @doc """
  Puts group data in cache.
  """
  @spec put_group(integer(), map()) :: :ok | {:error, Error.t()}
  def put_group(group_id, group_data) when is_integer(group_id) do
    case Helper.put("esi", "group:#{group_id}", group_data) do
      {:ok, true} -> :ok
      other -> other
    end
  end

  @doc """
  Clears a specific cache namespace.
  """
  @spec clear(atom()) :: :ok | {:error, Error.t()}
  def clear(cache_name) when cache_name in [:characters, :corporations, :alliances, :killmails] do
    Helper.clear_namespace(Atom.to_string(cache_name))
    :ok
  rescue
    error -> {:error, error}
  end

  @doc """
  Deletes a killmail from cache.
  """
  @spec delete_killmail(integer()) :: :ok | {:error, Error.t()}
  def delete_killmail(killmail_id) when is_integer(killmail_id) do
    case Helper.killmail_delete(killmail_id) do
      {:ok, _} -> :ok
      other -> other
    end
  end

  @doc """
  Gets data directly from cache by cache name and key (for testing).
  """
  @spec get_from_cache(atom(), term()) :: {:ok, map()} | {:error, Error.t()}
  def get_from_cache(cache_name, cache_key) do
    case Helper.get(Atom.to_string(cache_name), to_string(cache_key)) do
      {:ok, nil} ->
        {:error, Error.cache_error(:not_found, "Cache key not found")}

      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("Cache get failed",
          key: "#{Atom.to_string(cache_name)}:#{to_string(cache_key)}",
          reason: inspect(reason)
        )

        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @doc """
  Puts data directly into cache by cache name and key (for testing).
  """
  @spec put_in_cache(atom(), term(), map()) :: :ok | {:error, Error.t()}
  def put_in_cache(cache_name, cache_key, data) do
    case Helper.put(Atom.to_string(cache_name), to_string(cache_key), data) do
      {:ok, true} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache put failed",
          key: "#{Atom.to_string(cache_name)}:#{to_string(cache_key)}",
          reason: inspect(reason)
        )

        {:error, Error.cache_error(:put_failed, "Failed to put in cache", %{reason: reason})}
    end
  end

  @doc """
  Deletes data directly from cache by cache name and key (for testing).
  """
  @spec delete_from_cache(atom(), term()) :: :ok | {:error, Error.t()}
  def delete_from_cache(cache_name, cache_key) do
    case Helper.delete(Atom.to_string(cache_name), to_string(cache_key)) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache delete failed",
          key: "#{Atom.to_string(cache_name)}:#{to_string(cache_key)}",
          reason: inspect(reason)
        )

        {:error,
         Error.cache_error(:delete_failed, "Failed to delete from cache", %{reason: reason})}
    end
  end

  @doc """
  Gets cache statistics for all ESI-related caches.
  """
  @spec stats() :: [map()]
  def stats do
    case Helper.stats() do
      {:ok, stats} ->
        [Map.put(stats, :cache_name, :wanderer_cache)]

      {:error, _reason} ->
        [%{cache_name: :wanderer_cache, error: true}]
    end
  end

  @doc """
  Gets cache statistics for a specific namespace.
  """
  @spec stats(atom()) :: {:ok, map()} | {:error, Error.t()}
  def stats(cache_name) when cache_name in [:characters, :corporations, :alliances, :killmails] do
    Helper.stats()
  end
end
