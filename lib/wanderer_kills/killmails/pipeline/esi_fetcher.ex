defmodule WandererKills.Killmails.Pipeline.ESIFetcher do
  @moduledoc """
  ESI data fetching for killmail pipeline.

  This module handles fetching full killmail data from ESI
  and integrating with the cache system.
  """

  require Logger
  alias WandererKills.Cache.Helper
  alias WandererKills.Support.Error

  @type killmail :: map()

  @doc """
  Fetches full killmail data from ESI.

  First checks the cache, then fetches from ESI if needed.
  Caches successful results.
  """
  @spec fetch_full_killmail(integer(), map()) :: {:ok, killmail()} | {:error, Error.t()}
  def fetch_full_killmail(killmail_id, zkb) do
    with {:hash, hash} when not is_nil(hash) <- {:hash, Map.get(zkb, "hash")},
         {:cache, {:error, %WandererKills.Support.Error{type: :not_found}}} <-
           {:cache, Helper.get(:killmails, killmail_id)},
         {:esi, {:ok, esi_data}} when is_map(esi_data) <-
           {:esi, WandererKills.ESI.DataFetcher.get_killmail_raw(killmail_id, hash)} do
      # Cache the result
      Helper.put(:killmails, killmail_id, esi_data)
      {:ok, esi_data}
    else
      {:hash, nil} ->
        {:error, Error.killmail_error(:missing_hash, "Killmail hash not found in zkb data")}

      {:cache, {:ok, full_data}} ->
        {:ok, full_data}

      {:cache, {:error, reason}} ->
        {:error, reason}

      {:esi, {:error, reason}} ->
        Logger.error("Failed to fetch full killmail from ESI",
          killmail_id: killmail_id,
          hash: Map.get(zkb, "hash"),
          error: reason
        )

        {:error, reason}
    end
  end

  @doc """
  Stores enriched killmail data in cache after processing.
  """
  @spec cache_enriched_killmail(killmail()) :: :ok
  def cache_enriched_killmail(killmail) do
    Helper.put(:killmails, killmail["killmail_id"], killmail)
    :ok
  end
end
