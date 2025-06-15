defmodule WandererKills.Core.Systems.KillmailProcessor do
  @moduledoc """
  Processes killmail operations for systems.

  This module handles the processing and storage of killmails
  associated with specific systems, including enrichment and caching.
  """

  require Logger
  alias WandererKills.Core.Cache
  alias WandererKills.Ingest.Killmails.UnifiedProcessor

  # Compile-time configuration with sensible defaults
  @cutoff_hours Application.compile_env(:wanderer_kills, [:killmail_manager, :cutoff_hours], 24)
  @max_concurrency Application.compile_env(
                     :wanderer_kills,
                     [:killmail_manager, :max_concurrency],
                     10
                   )

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
    log_processing_start(system_id, length(killmails))

    with :ok <- update_system_timestamp(system_id),
         enriched_killmails <- process_and_enrich_killmails(killmails, system_id),
         :ok <- log_enrichment_results(system_id, enriched_killmails),
         killmail_ids <- cache_enriched_killmails(enriched_killmails, system_id),
         :ok <- log_caching_results(system_id, killmails, enriched_killmails, killmail_ids),
         :ok <- add_killmails_to_system(killmail_ids, system_id),
         :ok <- add_system_to_active_list(system_id) do
      :ok
    else
      error ->
        Logger.error("[KillmailProcessor] Error processing killmails for system",
          system_id: system_id,
          error: error
        )

        {:error, :processing_failed}
    end
  end

  # Process raw killmails through the parser/enricher pipeline
  defp process_and_enrich_killmails(raw_killmails, system_id) do
    cutoff_time = get_cutoff_time()

    # Process killmails in parallel with configurable concurrency limit
    raw_killmails
    |> Flow.from_enumerable(max_demand: get_max_concurrency())
    |> Flow.map(&process_single_killmail(&1, cutoff_time, system_id))
    |> Flow.filter(&(&1 != nil))
    |> Enum.to_list()
  end

  # Extract helper functions
  defp log_processing_start(system_id, killmail_count) do
    Logger.debug("[KillmailManager] Processing killmails for system",
      system_id: system_id,
      killmail_count: killmail_count
    )
  end

  defp update_system_timestamp(system_id) do
    Cache.mark_system_fetched(system_id, DateTime.utc_now())
    :ok
  end

  defp log_enrichment_results(system_id, enriched_killmails) do
    Logger.debug("[KillmailManager] Enriched killmails check",
      system_id: system_id,
      enriched_count: length(enriched_killmails),
      sample_killmail_keys: get_sample_killmail_keys(enriched_killmails)
    )

    :ok
  end

  defp log_caching_results(system_id, raw_killmails, enriched_killmails, killmail_ids) do
    Logger.debug("[KillmailManager] Processed and cached killmails",
      system_id: system_id,
      raw_count: length(raw_killmails),
      enriched_count: length(enriched_killmails),
      cached_count: length(killmail_ids)
    )

    :ok
  end

  defp add_system_to_active_list(system_id) do
    Cache.add_active_system(system_id)
    :ok
  end

  defp get_cutoff_time do
    DateTime.utc_now() |> DateTime.add(-@cutoff_hours * 60 * 60, :second)
  end

  defp get_max_concurrency do
    @max_concurrency
  end

  defp get_sample_killmail_keys(enriched_killmails) do
    if List.first(enriched_killmails) do
      Map.keys(List.first(enriched_killmails)) |> Enum.sort()
    else
      []
    end
  end

  defp process_single_killmail(killmail, cutoff_time, system_id) do
    try do
      case UnifiedProcessor.process_killmail(killmail, cutoff_time) do
        {:ok, :kill_older} ->
          log_killmail_too_old(killmail, system_id)
          nil

        {:ok, enriched} ->
          enriched

        {:error, reason} ->
          log_killmail_processing_failed(killmail, system_id, reason)
          nil
      end
    catch
      kind, error ->
        log_killmail_exception(killmail, system_id, kind, error)
        nil
    end
  end

  defp log_killmail_too_old(killmail, system_id) do
    Logger.debug("[KillmailManager] Kill older than cutoff",
      killmail_id: Map.get(killmail, "killmail_id"),
      system_id: system_id
    )
  end

  defp log_killmail_processing_failed(killmail, system_id, reason) do
    Logger.warning("[KillmailManager] Failed to process killmail",
      killmail_id: Map.get(killmail, "killmail_id"),
      system_id: system_id,
      error: reason
    )
  end

  defp log_killmail_exception(killmail, system_id, kind, error) do
    Logger.error("[KillmailManager] Exception processing killmail",
      killmail_id: Map.get(killmail, "killmail_id"),
      system_id: system_id,
      kind: kind,
      error: inspect(error)
    )
  end

  defp cache_enriched_killmails(enriched_killmails, system_id) do
    for killmail <- enriched_killmails,
        killmail_id = extract_killmail_id(killmail),
        not is_nil(killmail_id) do
      log_killmail_caching(killmail_id, system_id, killmail)
      cache_and_verify_killmail(killmail_id, killmail)
      killmail_id
    end
  end

  defp log_killmail_caching(killmail_id, system_id, killmail) do
    Logger.debug("[KillmailManager] Caching killmail",
      killmail_id: killmail_id,
      system_id: system_id,
      killmail_keys: Map.keys(killmail) |> Enum.sort()
    )
  end

  defp extract_killmail_id(killmail) do
    Map.get(killmail, "killmail_id") || Map.get(killmail, :killmail_id)
  end

  defp cache_and_verify_killmail(killmail_id, killmail) do
    case Cache.put(:killmails, killmail_id, killmail) do
      {:ok, _} ->
        log_killmail_cached_successfully(killmail_id)
        verify_cached_killmail(killmail_id)

      {:error, reason} ->
        log_killmail_caching_failed(killmail_id, reason)
    end
  end

  defp log_killmail_cached_successfully(killmail_id) do
    Logger.debug("[KillmailManager] Successfully cached killmail",
      killmail_id: killmail_id
    )
  end

  defp log_killmail_caching_failed(killmail_id, reason) do
    Logger.error("[KillmailManager] Failed to cache killmail",
      killmail_id: killmail_id,
      error: inspect(reason)
    )
  end

  defp verify_cached_killmail(killmail_id) do
    case Cache.get(:killmails, killmail_id) do
      {:ok, _retrieved} ->
        log_killmail_verification_success(killmail_id)

      {:error, reason} ->
        log_killmail_verification_failed(killmail_id, reason)
    end
  end

  defp log_killmail_verification_success(killmail_id) do
    Logger.debug("[KillmailManager] Verified killmail can be retrieved",
      killmail_id: killmail_id
    )
  end

  defp log_killmail_verification_failed(killmail_id, reason) do
    Logger.error("[KillmailManager] Cannot retrieve just-cached killmail!",
      killmail_id: killmail_id,
      error: inspect(reason)
    )
  end

  defp add_killmails_to_system(killmail_ids, system_id) do
    Enum.each(killmail_ids, &add_single_killmail_to_system(&1, system_id))
    :ok
  end

  defp add_single_killmail_to_system(killmail_id, system_id) do
    case Cache.add_system_killmail(system_id, killmail_id) do
      {:ok, _} ->
        log_killmail_added_to_system(system_id, killmail_id)

      {:error, reason} ->
        log_killmail_addition_failed(system_id, killmail_id, reason)
    end
  end

  defp log_killmail_added_to_system(system_id, killmail_id) do
    Logger.debug("[KillmailManager] Added killmail to system list",
      system_id: system_id,
      killmail_id: killmail_id
    )
  end

  defp log_killmail_addition_failed(system_id, killmail_id, reason) do
    Logger.error("[KillmailManager] Failed to add killmail to system list",
      system_id: system_id,
      killmail_id: killmail_id,
      error: inspect(reason)
    )
  end
end
