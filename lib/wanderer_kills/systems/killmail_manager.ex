defmodule WandererKills.Systems.KillmailManager do
  @moduledoc """
  Manages killmail operations for systems.
  
  This module handles the processing and storage of killmails
  associated with specific systems, including enrichment and caching.
  """
  
  require Logger
  alias WandererKills.Cache.Helper
  alias WandererKills.Killmails.UnifiedProcessor
  
  @doc """
  Process and cache killmails for a specific system.
  
  This function:
  1. Updates the system's fetch timestamp
  2. Processes killmails through the parser/enricher pipeline
  3. Caches individual enriched killmails by ID
  4. Associates killmail IDs with the system
  5. Adds the system to the active systems list
  
  ## Parameters
  - `system_id` - The solar system ID
  - `killmails` - List of raw killmail maps from ZKB
  
  ## Returns
  - `:ok` on success
  - `{:error, term()}` on failure
  """
  @spec process_system_killmails(integer(), [map()]) :: :ok | {:error, term()}
  def process_system_killmails(system_id, killmails) when is_list(killmails) do
    Logger.info("[KillmailManager] Processing killmails for system",
      system_id: system_id,
      killmail_count: length(killmails)
    )
    
    # Update fetch timestamp
    Helper.mark_system_fetched(system_id, DateTime.utc_now())
    
    # Process killmails through the pipeline to get enriched data
    enriched_killmails = process_and_enrich_killmails(killmails, system_id)
    
    # Extract killmail IDs and cache individual enriched killmails
    killmail_ids =
      for killmail <- enriched_killmails,
          killmail_id = Map.get(killmail, "killmail_id"),
          not is_nil(killmail_id) do
        # Cache the enriched killmail
        Helper.put(:killmails, killmail_id, killmail)
        killmail_id
      end
    
    Logger.info("[KillmailManager] Processed and cached killmails",
      system_id: system_id,
      raw_count: length(killmails),
      enriched_count: length(enriched_killmails),
      cached_count: length(killmail_ids)
    )
    
    # Add each killmail ID to system's killmail list
    Enum.each(killmail_ids, fn killmail_id ->
      Helper.add_system_killmail(system_id, killmail_id)
    end)
    
    # Add system to active list
    Helper.add_active_system(system_id)
    
    :ok
  rescue
    error ->
      Logger.error("[KillmailManager] Failed to process killmails",
        system_id: system_id,
        error: inspect(error)
      )
      {:error, :processing_failed}
  end
  
  # Process raw killmails through the parser/enricher pipeline
  defp process_and_enrich_killmails(raw_killmails, system_id) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-24 * 60 * 60, :second)
    
    # Process killmails in parallel with a reasonable concurrency limit using Flow
    raw_killmails
    |> Flow.from_enumerable(max_demand: 10)
    |> Flow.map(fn killmail ->
      try do
        # Use Processor to handle partial killmails
        case UnifiedProcessor.process_killmail(killmail, cutoff_time) do
          {:ok, :kill_older} ->
            Logger.debug("[KillmailManager] Kill older than cutoff",
              killmail_id: Map.get(killmail, "killmail_id"),
              system_id: system_id
            )
            nil
            
          {:ok, enriched} ->
            enriched
            
          {:error, reason} ->
            Logger.warning("[KillmailManager] Failed to process killmail",
              killmail_id: Map.get(killmail, "killmail_id"),
              system_id: system_id,
              error: reason
            )
            nil
        end
      catch
        kind, error ->
          Logger.error("[KillmailManager] Exception processing killmail",
            killmail_id: Map.get(killmail, "killmail_id"),
            system_id: system_id,
            kind: kind,
            error: inspect(error)
          )
          nil
      end
    end)
    |> Flow.filter(&(&1 != nil))
    |> Flow.partition()
    |> Enum.to_list()
  end
end