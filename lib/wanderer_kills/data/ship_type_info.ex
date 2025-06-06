defmodule WandererKills.Data.ShipTypeInfo do
  @moduledoc """
  Simplified ship type information handler using ESI caching.

  This module provides a lightweight interface for ship type data by leveraging
  the existing ESI caching infrastructure.
  """

  require Logger
  alias WandererKills.Cache

  @doc """
  Gets ship type information from the ESI cache.

  This function first tries to get the data from cache, and if not found,
  falls back to ESI API as needed.
  """
  @spec get_ship_type(integer()) :: {:ok, map()} | {:error, term()}
  def get_ship_type(type_id) when is_integer(type_id) and type_id > 0 do
    Cache.get_type_info(type_id)
  end

  def get_ship_type(_type_id), do: {:error, :invalid_type_id}

  @doc """
  Warms the cache with CSV data if needed.

  This is called during application startup to populate the cache
  with local CSV data before relying on ESI API calls.
  """
  @spec warm_cache() :: :ok | {:error, term()}
  def warm_cache do
    Logger.info("Warming ship type cache with CSV data")

    # Use the updater which handles downloading missing CSV files
    case WandererKills.Data.ShipTypeUpdater.update_with_csv() do
      :ok ->
        Logger.info("Successfully warmed cache with CSV data")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to warm cache with CSV data: #{inspect(reason)}")
        # Don't fail if CSV loading fails - ESI fallback will work
        :ok
    end
  end
end
