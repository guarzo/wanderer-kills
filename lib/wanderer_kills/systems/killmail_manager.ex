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
    Logger.debug("[KillmailManager] Processing killmails for system",
      system_id: system_id,
      killmail_count: length(killmails)
    )

    # Update fetch timestamp
    Helper.mark_system_fetched(system_id, DateTime.utc_now())

    # Process killmails through the pipeline to get enriched data
    enriched_killmails = process_and_enrich_killmails(killmails, system_id)

    Logger.debug("[KillmailManager] Enriched killmails check",
      system_id: system_id,
      enriched_count: length(enriched_killmails),
      sample_killmail_keys:
        if(List.first(enriched_killmails),
          do: Map.keys(List.first(enriched_killmails)) |> Enum.sort(),
          else: []
        )
    )

    # Extract killmail IDs and cache individual enriched killmails
    killmail_ids = cache_enriched_killmails(enriched_killmails, system_id)

    Logger.debug("[KillmailManager] Processed and cached killmails",
      system_id: system_id,
      raw_count: length(killmails),
      enriched_count: length(enriched_killmails),
      cached_count: length(killmail_ids)
    )

    # Add each killmail ID to system's killmail list
    add_killmails_to_system(killmail_ids, system_id)

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

  defp cache_enriched_killmails(enriched_killmails, system_id) do
    for killmail <- enriched_killmails,
        killmail_id = extract_killmail_id(killmail),
        not is_nil(killmail_id) do
      Logger.debug("[KillmailManager] Caching killmail",
        killmail_id: killmail_id,
        system_id: system_id,
        killmail_keys: Map.keys(killmail) |> Enum.sort()
      )

      cache_and_verify_killmail(killmail_id, killmail)
      killmail_id
    end
  end

  defp extract_killmail_id(killmail) do
    Map.get(killmail, "killmail_id") || Map.get(killmail, :killmail_id)
  end

  defp cache_and_verify_killmail(killmail_id, killmail) do
    case Helper.put(:killmails, killmail_id, killmail) do
      {:ok, _} ->
        Logger.debug("[KillmailManager] Successfully cached killmail",
          killmail_id: killmail_id
        )

        verify_cached_killmail(killmail_id)

      {:error, reason} ->
        Logger.error("[KillmailManager] Failed to cache killmail",
          killmail_id: killmail_id,
          error: inspect(reason)
        )
    end
  end

  defp verify_cached_killmail(killmail_id) do
    case Helper.get(:killmails, killmail_id) do
      {:ok, _retrieved} ->
        Logger.debug("[KillmailManager] Verified killmail can be retrieved",
          killmail_id: killmail_id
        )

      {:error, reason} ->
        Logger.error("[KillmailManager] Cannot retrieve just-cached killmail!",
          killmail_id: killmail_id,
          error: inspect(reason)
        )
    end
  end

  defp add_killmails_to_system(killmail_ids, system_id) do
    Enum.each(killmail_ids, fn killmail_id ->
      case Helper.add_system_killmail(system_id, killmail_id) do
        {:ok, _} ->
          Logger.debug("[KillmailManager] Added killmail to system list",
            system_id: system_id,
            killmail_id: killmail_id
          )

        {:error, reason} ->
          Logger.error("[KillmailManager] Failed to add killmail to system list",
            system_id: system_id,
            killmail_id: killmail_id,
            error: inspect(reason)
          )
      end
    end)
  end
end
