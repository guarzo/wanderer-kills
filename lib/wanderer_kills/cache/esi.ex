defmodule WandererKills.Cache.ESI do
  @moduledoc """
  Domain-specific cache wrapper for ESI data.

  This module encapsulates all Cachex operations for ESI-related data
  including characters, corporations, alliances, and killmails,
  providing a clean interface for business logic without direct
  Cachex dependencies.
  """

  alias WandererKills.Core.{Config, Error}
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
  @spec get_character(integer()) :: {:ok, map()} | {:error, Error.t()}
  def get_character(character_id) when is_integer(character_id) do
    get_from_cache(:characters, character_id)
  end

  @doc """
  Gets character data from cache or sets it using a fallback function.
  """
  @spec get_or_set_character(integer(), (-> map())) :: {:ok, map()} | {:error, Error.t()}
  def get_or_set_character(character_id, fallback_fn) when is_integer(character_id) do
    get_or_set_from_cache(:characters, character_id, fallback_fn)
  end

  @doc """
  Puts character data in cache.
  """
  @spec put_character(integer(), map()) :: :ok | {:error, Error.t()}
  def put_character(character_id, character_data) when is_integer(character_id) do
    put_in_cache(:characters, character_id, character_data)
  end

  @doc """
  Gets corporation data from cache.
  """
  @spec get_corporation(integer()) :: {:ok, map()} | {:error, Error.t()}
  def get_corporation(corporation_id) when is_integer(corporation_id) do
    get_from_cache(:corporations, corporation_id)
  end

  @doc """
  Gets corporation data from cache or sets it using a fallback function.
  """
  @spec get_or_set_corporation(integer(), (-> map())) :: {:ok, map()} | {:error, Error.t()}
  def get_or_set_corporation(corporation_id, fallback_fn) when is_integer(corporation_id) do
    get_or_set_from_cache(:corporations, corporation_id, fallback_fn)
  end

  @doc """
  Puts corporation data in cache.
  """
  @spec put_corporation(integer(), map()) :: :ok | {:error, Error.t()}
  def put_corporation(corporation_id, corporation_data) when is_integer(corporation_id) do
    put_in_cache(:corporations, corporation_id, corporation_data)
  end

  @doc """
  Gets alliance data from cache.
  """
  @spec get_alliance(integer()) :: {:ok, map()} | {:error, Error.t()}
  def get_alliance(alliance_id) when is_integer(alliance_id) do
    get_from_cache(:alliances, alliance_id)
  end

  @doc """
  Gets alliance data from cache or sets it using a fallback function.
  """
  @spec get_or_set_alliance(integer(), (-> map())) :: {:ok, map()} | {:error, Error.t()}
  def get_or_set_alliance(alliance_id, fallback_fn) when is_integer(alliance_id) do
    get_or_set_from_cache(:alliances, alliance_id, fallback_fn)
  end

  @doc """
  Puts alliance data in cache.
  """
  @spec put_alliance(integer(), map()) :: :ok | {:error, Error.t()}
  def put_alliance(alliance_id, alliance_data) when is_integer(alliance_id) do
    put_in_cache(:alliances, alliance_id, alliance_data)
  end

  @doc """
  Gets killmail data from cache.
  """
  @spec get_killmail(integer()) :: {:ok, map()} | {:error, Error.t()}
  def get_killmail(killmail_id) when is_integer(killmail_id) do
    get_from_cache(:killmails, killmail_id)
  end

  @doc """
  Gets killmail data from cache or sets it using a fallback function.
  """
  @spec get_or_set_killmail(integer(), (-> map())) :: {:ok, map()} | {:error, Error.t()}
  def get_or_set_killmail(killmail_id, fallback_fn) when is_integer(killmail_id) do
    get_or_set_from_cache(:killmails, killmail_id, fallback_fn, :esi_killmail)
  end

  @doc """
  Puts killmail data in cache.
  """
  @spec put_killmail(integer(), map()) :: :ok | {:error, Error.t()}
  def put_killmail(killmail_id, killmail_data) when is_integer(killmail_id) do
    put_in_cache(:killmails, killmail_id, killmail_data, :esi_killmail)
  end

  @doc """
  Gets type data from cache.
  """
  @spec get_type(integer()) :: {:ok, map()} | {:error, Error.t()}
  def get_type(type_id) when is_integer(type_id) do
    # Types are stored in the ship_types cache
    ShipTypes.get(type_id)
  end

  @doc """
  Gets type data from cache or sets it using a fallback function.
  """
  @spec get_or_set_type(integer(), (-> map())) :: {:ok, map()} | {:error, Error.t()}
  def get_or_set_type(type_id, fallback_fn) when is_integer(type_id) do
    # Types are stored in the ship_types cache
    ShipTypes.get_or_set(type_id, fallback_fn)
  end

  @doc """
  Puts type data in cache.
  """
  @spec put_type(integer(), map()) :: :ok | {:error, Error.t()}
  def put_type(type_id, type_data) when is_integer(type_id) do
    # Types are stored in the ship_types cache
    ShipTypes.put(type_id, type_data)
  end

  @doc """
  Gets group data from cache.
  """
  @spec get_group(integer()) :: {:ok, map()} | {:error, Error.t()}
  def get_group(group_id) when is_integer(group_id) do
    get_from_cache(:esi, group_id, "group")
  end

  @doc """
  Gets group data from cache or sets it using a fallback function.
  """
  @spec get_or_set_group(integer(), (-> map())) :: {:ok, map()} | {:error, Error.t()}
  def get_or_set_group(group_id, fallback_fn) when is_integer(group_id) do
    get_or_set_from_cache(:esi, group_id, fallback_fn, "group")
  end

  @doc """
  Puts group data in cache.
  """
  @spec put_group(integer(), map()) :: :ok | {:error, Error.t()}
  def put_group(group_id, group_data) when is_integer(group_id) do
    put_in_cache(:esi, group_id, group_data, "group")
  end

  @doc """
  Clears a specific cache namespace.
  """
  @spec clear(atom()) :: :ok | {:error, Error.t()}
  def clear(cache_name) when cache_name in [:characters, :corporations, :alliances, :killmails] do
    case Cachex.clear(cache_name) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache clear failed", cache: cache_name, reason: inspect(reason))
        {:error, Error.cache_error(:clear_failed, "Failed to clear cache", %{reason: reason})}
    end
  end

  @doc """
  Gets cache statistics for a specific namespace.
  """
  @spec stats(atom()) :: {:ok, map()} | {:error, Error.t()}
  def stats(cache_name) when cache_name in [:characters, :corporations, :alliances, :killmails] do
    case Cachex.stats(cache_name) do
      {:ok, stats} ->
        {:ok, stats}

      {:error, reason} ->
        Logger.error("Cache stats failed", cache: cache_name, reason: inspect(reason))
        {:error, Error.cache_error(:stats_failed, "Failed to get cache stats", %{reason: reason})}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec get_from_cache(atom(), integer()) :: {:ok, map()} | {:error, Error.t()}
  defp get_from_cache(cache_name, id) do
    cache_key = key(cache_name, id)

    case Cachex.get(cache_name, cache_key) do
      {:ok, nil} ->
        {:error, Error.cache_error(:not_found, "#{cache_name} not found in cache")}

      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("Cache get failed", key: cache_key, reason: inspect(reason))
        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @spec get_from_cache(atom(), integer(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  defp get_from_cache(cache_name, id, prefix) do
    cache_key = key(cache_name, id, prefix)

    case Cachex.get(cache_name, cache_key) do
      {:ok, nil} ->
        {:error, Error.cache_error(:not_found, "#{prefix} not found in cache")}

      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("Cache get failed", key: cache_key, reason: inspect(reason))
        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @spec get_or_set_from_cache(atom(), integer(), (-> map()), atom() | nil) ::
          {:ok, map()} | {:error, Error.t()}
  defp get_or_set_from_cache(cache_name, id, fallback_fn, ttl_type \\ nil) do
    cache_key = key(cache_name, id)
    ttl_type = ttl_type || :esi

    case Cachex.fetch(cache_name, cache_key, fn _key ->
           try do
             {:commit, fallback_fn.()}
           rescue
             error ->
               Logger.error("Cache fallback function failed",
                 key: cache_key,
                 error: inspect(error)
               )

               {:ignore, error}
           end
         end) do
      {:ok, value} ->
        {:ok, value}

      {:commit, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("Cache fetch failed", key: cache_key, reason: inspect(reason))

        {:error,
         Error.cache_error(:fetch_failed, "Failed to fetch from cache", %{reason: reason})}
    end
  end

  @spec put_in_cache(atom(), integer(), map(), atom() | nil) :: :ok | {:error, Error.t()}
  defp put_in_cache(cache_name, id, data, ttl_type \\ nil) do
    cache_key = key(cache_name, id)
    ttl_type = ttl_type || :esi
    ttl_ms = Config.cache_ttl(ttl_type) * 1000

    case Cachex.put(cache_name, cache_key, data, ttl: ttl_ms) do
      {:ok, true} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache put failed", key: cache_key, reason: inspect(reason))
        {:error, Error.cache_error(:put_failed, "Failed to put in cache", %{reason: reason})}
    end
  end
end
