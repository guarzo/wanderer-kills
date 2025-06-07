defmodule WandererKills.Cache.ShipTypes do
  @moduledoc """
  Domain-specific cache wrapper for ship type data.

  **DEPRECATED**: This module is now a thin wrapper around `WandererKills.Cache.Helper`.
  Use `Helper.ship_type_*` functions directly for new code.

  This module encapsulates all Cachex operations for ship types,
  providing a clean interface for business logic without direct
  Cachex dependencies.
  """

  alias WandererKills.Cache.Helper

  @doc """
  Generates a cache key for a ship type ID.
  """
  @spec key(integer()) :: String.t()
  def key(type_id) when is_integer(type_id) do
    "ship_types:#{type_id}"
  end

  @doc """
  Gets a ship type from cache.
  """
  @spec get(integer()) :: {:ok, map()} | {:error, term()}
  def get(type_id) when is_integer(type_id) do
    Helper.ship_type_get(type_id)
  end

  @doc """
  Gets a ship type from cache or sets it using a fallback function.
  """
  @spec get_or_set(integer(), (-> map())) :: {:ok, map()} | {:error, term()}
  def get_or_set(type_id, fallback_fn) when is_integer(type_id) and is_function(fallback_fn, 0) do
    Helper.ship_type_get_or_set(type_id, fallback_fn)
  end

  @doc """
  Puts a ship type in cache.
  """
  @spec put(integer(), map()) :: :ok | {:error, term()}
  def put(type_id, ship_type) when is_integer(type_id) and is_map(ship_type) do
    Helper.ship_type_put(type_id, ship_type)
  end

  @doc """
  Deletes a ship type from cache.
  """
  @spec delete(integer()) :: :ok | {:error, term()}
  def delete(type_id) when is_integer(type_id) do
    Helper.ship_type_delete(type_id)
  end

  @doc """
  Clears all ship types from cache.
  """
  @spec clear() :: :ok | {:error, term()}
  def clear do
    Helper.clear_namespace("ship_types")
    :ok
  rescue
    error -> {:error, error}
  end

  @doc """
  Gets cache statistics.
  """
  @spec stats() :: {:ok, map()} | {:error, term()}
  def stats do
    Helper.stats()
  end
end
