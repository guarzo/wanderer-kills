defmodule WandererKills.Ingest.Killmails.Pipeline.ESIFetcher do
  @moduledoc """
  ESI data fetching for killmail pipeline.

  This module handles fetching full killmail data from ESI
  and integrating with the cache system.
  """

  require Logger

  alias WandererKills.Core.Cache
  alias WandererKills.Core.Support.Error
  alias WandererKills.Ingest.ESI.Client

  @type killmail :: map()

  @doc """
  Fetches full killmail data from ESI.

  First checks the cache, then fetches from ESI if needed.
  Caches successful results.
  """
  @spec fetch_full_killmail(integer(), map()) :: {:ok, killmail()} | {:error, Error.t()}
  def fetch_full_killmail(killmail_id, zkb) do
    with {:hash, hash} when is_binary(hash) and byte_size(hash) > 0 <-
           {:hash, Map.get(zkb, "hash")},
         {:cache, {:error, %WandererKills.Core.Support.Error{type: :not_found}}} <-
           {:cache, Cache.get(:killmails, killmail_id)},
         {:esi, {:ok, esi_data}} when is_map(esi_data) <-
           {:esi, Client.get_killmail_raw(killmail_id, hash)} do
      # Cache the result
      Cache.put(:killmails, killmail_id, esi_data)
      {:ok, esi_data}
    else
      {:hash, hash} when is_nil(hash) or hash == "" ->
        {:error,
         Error.killmail_error(:missing_hash, "Killmail hash not found or empty in zkb data")}

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
    Cache.put(:killmails, killmail["killmail_id"], killmail)
    :ok
  end
end
