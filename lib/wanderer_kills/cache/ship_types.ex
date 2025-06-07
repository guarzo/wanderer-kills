defmodule WandererKills.Cache.ShipTypes do
  @moduledoc """
  Domain-specific cache wrapper for ship type data.

  This module encapsulates all Cachex operations for ship types,
  providing a clean interface for business logic without direct
  Cachex dependencies.
  """

  alias WandererKills.Core.Error
  alias WandererKills.Cache.Helper
  require Logger

  @namespace "ship_types"

  @doc """
  Generates a cache key for a ship type ID.
  """
  @spec key(integer()) :: String.t()
  def key(type_id) when is_integer(type_id) do
    "ship_type:#{type_id}"
  end

  @doc """
  Gets a ship type from cache.
  """
  @spec get(integer()) :: {:ok, map()} | {:error, Error.t()}
  def get(type_id) when is_integer(type_id) do
    cache_key = to_string(type_id)

    case Helper.get(@namespace, cache_key) do
      {:ok, nil} ->
        {:error, Error.cache_error(:not_found, "Ship type not found in cache")}

      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("Cache get failed",
          key: "#{@namespace}:#{cache_key}",
          reason: inspect(reason)
        )

        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @doc """
  Gets a ship type from cache or sets it using a fallback function.
  """
  @spec get_or_set(integer(), (-> map())) :: {:ok, map()} | {:error, Error.t()}
  def get_or_set(type_id, fallback_fn) when is_integer(type_id) and is_function(fallback_fn, 0) do
    cache_key = to_string(type_id)

    case Helper.fetch(@namespace, cache_key, fn _key ->
           try do
             {:commit, fallback_fn.()}
           rescue
             error ->
               Logger.error("Cache fallback function failed",
                 key: "#{@namespace}:#{cache_key}",
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
        Logger.error("Cache fetch failed",
          key: "#{@namespace}:#{cache_key}",
          reason: inspect(reason)
        )

        {:error,
         Error.cache_error(:fetch_failed, "Failed to fetch from cache", %{reason: reason})}
    end
  end

  @doc """
  Puts a ship type in cache.
  """
  @spec put(integer(), map()) :: :ok | {:error, Error.t()}
  def put(type_id, ship_type) when is_integer(type_id) and is_map(ship_type) do
    cache_key = to_string(type_id)

    case Helper.put(@namespace, cache_key, ship_type) do
      {:ok, true} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache put failed",
          key: "#{@namespace}:#{cache_key}",
          reason: inspect(reason)
        )

        {:error, Error.cache_error(:put_failed, "Failed to put in cache", %{reason: reason})}
    end
  end

  @doc """
  Deletes a ship type from cache.
  """
  @spec delete(integer()) :: :ok | {:error, Error.t()}
  def delete(type_id) when is_integer(type_id) do
    cache_key = to_string(type_id)

    case Helper.delete(@namespace, cache_key) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache delete failed",
          key: "#{@namespace}:#{cache_key}",
          reason: inspect(reason)
        )

        {:error,
         Error.cache_error(:delete_failed, "Failed to delete from cache", %{reason: reason})}
    end
  end

  @doc """
  Clears all ship types from cache.
  """
  @spec clear() :: :ok | {:error, Error.t()}
  def clear do
    try do
      Helper.clear_namespace(@namespace)
      :ok
    rescue
      error ->
        Logger.error("Cache clear failed", reason: inspect(error))
        {:error, Error.cache_error(:clear_failed, "Failed to clear cache", %{reason: error})}
    end
  end

  @doc """
  Gets cache statistics.
  """
  @spec stats() :: {:ok, map()} | {:error, Error.t()}
  def stats do
    case Helper.stats() do
      {:ok, stats} ->
        {:ok, stats}

      {:error, reason} ->
        Logger.error("Cache stats failed", reason: inspect(reason))
        {:error, Error.cache_error(:stats_failed, "Failed to get cache stats", %{reason: reason})}
    end
  end
end
