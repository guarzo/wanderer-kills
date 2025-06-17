defmodule WandererKills.Core.ShipTypes.Info do
  @moduledoc """
  Ship type information handler for the ship types domain.

  This module provides ship type data access by leveraging
  the existing ESI caching infrastructure and CSV data sources.
  """

  require Logger
  alias WandererKills.Core.Cache
  alias WandererKills.Core.ShipTypes.Updater
  alias WandererKills.Core.Support.Error

  @doc """
  Gets ship type information from the ESI cache.

  This function first tries to get the data from cache, and if not found,
  falls back to ESI API as needed.
  """
  @spec get_ship_type(integer()) :: {:ok, map()} | {:error, term()}
  def get_ship_type(type_id) when is_integer(type_id) and type_id > 0 do
    Cache.get(:ship_types, type_id)
  end

  def get_ship_type(_type_id) do
    {:error, Error.ship_types_error(:invalid_type_id, "Type ID must be a positive integer")}
  end

  @doc """
  Warms the cache with CSV data if needed.

  This is called during application startup to populate the cache
  with local CSV data before relying on ESI API calls.
  """
  @spec warm_cache() :: :ok | {:error, term()}
  def warm_cache do
    Logger.debug("Warming ship type cache with CSV data")

    # Use the updater which handles downloading missing CSV files
    case Updater.update_with_csv() do
      :ok ->
        Logger.debug("Successfully warmed cache with CSV data")
        :ok

      {:error, _reason} = error ->
        Logger.warning("Failed to warm cache with CSV data: #{inspect(error)}")
        # Don't fail if CSV loading fails - ESI fallback will work
        :ok
    end
  end
end
