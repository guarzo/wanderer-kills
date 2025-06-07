defmodule WandererKills.ShipTypes.Info do
  @moduledoc """
  Ship type information handler for the ship types domain.

  This module provides ship type data access by leveraging
  the existing ESI caching infrastructure and CSV data sources.
  """

  require Logger
  alias WandererKills.Cache.Helper
  alias WandererKills.Infrastructure.Error

  @doc """
  Gets ship type information from the ESI cache.

  This function first tries to get the data from cache, and if not found,
  falls back to ESI API as needed.
  """
  @spec get_ship_type(integer()) :: {:ok, map()} | {:error, term()}
  def get_ship_type(type_id) when is_integer(type_id) and type_id > 0 do
    Helper.ship_type_get(type_id)
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
    Logger.info("Warming ship type cache with CSV data")

    # Use the updater which handles downloading missing CSV files
    case WandererKills.ShipTypes.Updater.update_with_csv() do
      :ok ->
        Logger.info("Successfully warmed cache with CSV data")
        :ok

      result ->
        Logger.warning("Failed to warm cache with CSV data: #{inspect(result)}")
        # Don't fail if CSV loading fails - ESI fallback will work
        :ok
    end
  end
end
