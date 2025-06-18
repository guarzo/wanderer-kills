defmodule WandererKills.Subs.Preloader do
  @moduledoc """
  Shared preload logic for killmails across different channels.

  This module consolidates the common preload functionality used by:
  - WebSocket channels (KillmailChannel)
  - Webhook subscriptions (SubscriptionManager)

  It provides consistent killmail preloading with:
  - Cache-first approach
  - Fallback to fresh fetch from ZKillboard
  - Enrichment through the pipeline
  - Time-based filtering
  - Consistent logging
  """

  require Logger

  alias WandererKills.Core.Cache
  alias WandererKills.Core.Systems.KillmailProcessor
  alias WandererKills.Domain.Killmail
  alias WandererKills.Ingest.Killmails.ZkbClient

  @type system_id :: integer()
  @type killmail :: Killmail.t()
  @type limit :: pos_integer()
  @type hours :: pos_integer()

  @doc """
  Preloads kills for a system with a specified limit.

  This function:
  1. Checks cache for existing killmail IDs
  2. If not found, fetches fresh kills from ZKillboard
  3. Enriches the killmails through the pipeline
  4. Returns the most recent enriched killmails up to the limit

  ## Parameters
    - `system_id` - The EVE Online solar system ID
    - `limit` - Maximum number of kills to return
    - `since_hours` - How many hours back to fetch (for fresh fetches)

  ## Returns
    - List of enriched killmail structs
  """
  @spec preload_kills_for_system(system_id(), limit(), hours()) :: [Killmail.t()]
  def preload_kills_for_system(system_id, limit, since_hours \\ 24) do
    Logger.debug("[DEBUG] Preloading kills for system",
      system_id: system_id,
      limit: limit,
      since_hours: since_hours
    )

    result =
      case Cache.list_system_killmails(system_id) do
        {:ok, killmail_ids} when is_list(killmail_ids) and killmail_ids != [] ->
          Logger.debug("[DEBUG] Found cached killmails, using cache",
            system_id: system_id,
            cached_count: length(killmail_ids)
          )

          get_enriched_killmails(killmail_ids, limit)

        _ ->
          Logger.debug("[DEBUG] No cached killmails found, fetching fresh data",
            system_id: system_id
          )

          fetch_and_cache_fresh_kills(system_id, limit, since_hours)
      end

    Logger.debug("[DEBUG] Preload completed",
      system_id: system_id,
      returned_count: length(result),
      requested_limit: limit
    )

    result
  end

  @doc """
  Gets enriched killmails from cache by their IDs.

  ## Parameters
    - `killmail_ids` - List of killmail IDs to get
    - `limit` - Maximum number of kills to return
    - `filter_recent` - Whether to filter by recency (default: true)

  ## Returns
    - List of enriched killmail structs
  """
  @spec get_enriched_killmails([integer()], limit(), boolean()) :: [Killmail.t()]
  def get_enriched_killmails(killmail_ids, limit, filter_recent \\ true) do
    Logger.debug("[DEBUG] get_enriched_killmails called", %{
      killmail_ids_count: length(killmail_ids),
      limit: limit,
      filter_recent: filter_recent
    })

    # Only include kills from the last hour if filtering is enabled
    cutoff_time =
      if filter_recent do
        now = DateTime.utc_now()
        cutoff = DateTime.add(now, -1 * 60 * 60, :second)

        Logger.debug("[DEBUG] Calculated cutoff time for filtering", %{
          current_time: DateTime.to_iso8601(now),
          cutoff_time: DateTime.to_iso8601(cutoff),
          hours_back: 1
        })

        cutoff
      else
        nil
      end

    fetched_kills =
      killmail_ids
      # Take more to account for filtering
      |> Enum.take(limit * 2)
      |> Enum.map(&get_single_enriched_killmail/1)
      |> Enum.reduce([], fn
        {:ok, killmail}, acc ->
          Logger.debug("[DEBUG] Retrieved killmail from cache", %{
            killmail_id: killmail["killmail_id"]
          })

          [killmail | acc]

        {:error, reason}, acc ->
          Logger.debug("[DEBUG] Failed to retrieve killmail from cache", %{
            error: inspect(reason)
          })

          acc
      end)

    Logger.debug("[DEBUG] Fetched kills before filtering",
      count: length(fetched_kills)
    )

    result =
      fetched_kills
      |> Enum.reverse()
      |> maybe_filter_recent(cutoff_time)
      |> Enum.take(limit)

    Logger.debug("[DEBUG] Final result after filtering",
      count: length(result)
    )

    result
  end

  @doc """
  Extracts kill times from a list of killmails.

  Handles both `kill_time` and legacy `killmail_time` fields.
  """
  @spec extract_kill_times([Killmail.t() | map()]) :: [String.t()]
  def extract_kill_times(kills) do
    Enum.map(kills, fn
      %Killmail{kill_time: time} ->
        if time, do: to_string(time), else: "unknown"

      kill_map when is_map(kill_map) ->
        # Handle map case - try to extract kill_time directly
        case kill_map["kill_time"] || kill_map[:kill_time] do
          nil -> "unknown"
          time -> to_string(time)
        end

      _ ->
        "unknown"
    end)
  end

  @doc """
  Counts how many kills have enriched data (character names).

  A kill is considered enriched if it has:
  - Victim character name, OR
  - At least one attacker with a character name
  """
  @spec count_enriched_kills([Killmail.t() | map()]) :: non_neg_integer()
  def count_enriched_kills(kills) do
    Enum.count(kills, &enriched_kill?/1)
  end

  defp enriched_kill?(kill) do
    case ensure_killmail_struct(kill) do
      %Killmail{} = killmail -> has_character_names?(killmail)
      _ -> false
    end
  end

  defp has_character_names?(%Killmail{victim: victim, attackers: attackers}) do
    has_victim_name?(victim) or has_attacker_with_name?(attackers)
  end

  defp has_victim_name?(nil), do: false
  defp has_victim_name?(victim), do: victim.character_name != nil

  defp has_attacker_with_name?(attackers) do
    Enum.any?(attackers, fn attacker -> attacker.character_name != nil end)
  end

  @doc """
  Checks if a killmail is recent enough based on cutoff time.
  """
  @spec killmail_recent?(Killmail.t() | map(), DateTime.t()) :: boolean()

  # Handle map input by converting to struct first
  def killmail_recent?(killmail_map, cutoff_time)
      when is_map(killmail_map) and not is_struct(killmail_map) do
    case ensure_killmail_struct(killmail_map) do
      %Killmail{} = killmail ->
        killmail_recent?(killmail, cutoff_time)

      _ ->
        Logger.warning("[WARNING] Failed to convert killmail map to struct in killmail_recent?",
          killmail_id: killmail_map["killmail_id"] || killmail_map[:killmail_id]
        )

        false
    end
  end

  def killmail_recent?(%Killmail{killmail_id: killmail_id, kill_time: kill_time}, cutoff_time) do
    case kill_time do
      %DateTime{} = dt ->
        result = DateTime.compare(dt, cutoff_time) == :gt

        Logger.debug("[DEBUG] Checking if killmail is recent",
          killmail_id: killmail_id,
          kill_time: DateTime.to_iso8601(dt),
          cutoff_time: DateTime.to_iso8601(cutoff_time),
          comparison_result: DateTime.compare(dt, cutoff_time),
          is_recent: result
        )

        result

      time_string when is_binary(time_string) ->
        case DateTime.from_iso8601(time_string) do
          {:ok, dt, _offset} ->
            result = DateTime.compare(dt, cutoff_time) == :gt

            Logger.debug("[DEBUG] Checking if killmail is recent (parsed from string)",
              killmail_id: killmail_id,
              kill_time_string: time_string,
              kill_time_parsed: DateTime.to_iso8601(dt),
              cutoff_time: DateTime.to_iso8601(cutoff_time),
              comparison_result: DateTime.compare(dt, cutoff_time),
              is_recent: result
            )

            result

          {:error, _} ->
            Logger.error("Failed to parse kill_time",
              killmail_id: killmail_id,
              kill_time: time_string
            )

            false
        end

      nil ->
        Logger.error("Enriched killmail missing kill_time",
          killmail_id: killmail_id
        )

        false

      other ->
        Logger.error("Enriched killmail has invalid kill_time format",
          killmail_id: killmail_id,
          kill_time_type: inspect(other),
          kill_time_value: inspect(other, limit: 100)
        )

        false
    end
  end

  @doc """
  Logs a summary of preloaded kills.
  """
  @spec log_preload_summary(map(), system_id(), [Killmail.t()]) :: :ok
  def log_preload_summary(context, system_id, kills) do
    killmail_ids = Enum.map(kills, & &1.killmail_id)
    kill_times = extract_kill_times(kills)
    enriched_count = count_enriched_kills(kills)

    Logger.debug(
      "[DEBUG] Preload summary",
      Map.merge(context, %{
        system_id: system_id,
        kill_count: length(kills),
        killmail_ids: killmail_ids,
        enriched_count: enriched_count,
        unenriched_count: length(kills) - enriched_count,
        kill_time_range: kill_time_range(kill_times)
      })
    )

    log_sample_kill(kills)
    :ok
  end

  # Private functions

  defp ensure_killmail_struct(%Killmail{} = killmail), do: killmail

  defp ensure_killmail_struct(killmail_map) when is_map(killmail_map) do
    case Killmail.new(killmail_map) do
      {:ok, killmail} ->
        killmail

      {:error, reason} ->
        Logger.warning("[WARNING] Failed to convert killmail map to struct",
          killmail_id: killmail_map["killmail_id"] || killmail_map[:killmail_id],
          error: inspect(reason)
        )

        nil
    end
  end

  defp ensure_killmail_struct(_), do: nil

  defp fetch_and_cache_fresh_kills(system_id, limit, since_hours) do
    Logger.debug("[DEBUG] Fetching fresh kills from ZKillboard",
      system_id: system_id,
      limit: limit,
      since_hours: since_hours
    )

    # Convert since_hours to options for the new API
    past_seconds = since_hours * 3600
    opts = [past_seconds: past_seconds, limit: 50]

    case ZkbClient.fetch_system_killmails(system_id, opts) do
      {:ok, fresh_kills} when is_list(fresh_kills) ->
        # Only process the number of kills we need for preload
        kills_to_cache = Enum.take(fresh_kills, limit)

        Logger.debug("[DEBUG] Processing fresh kills through pipeline",
          system_id: system_id,
          fetched_count: length(fresh_kills),
          processing_count: length(kills_to_cache)
        )

        # Cache the kills through the pipeline
        KillmailProcessor.process_system_killmails(system_id, kills_to_cache)

        Logger.debug("[DEBUG] Fresh kills cached successfully",
          system_id: system_id,
          cached_count: length(kills_to_cache)
        )

        # Now get the enriched killmails from cache
        case Cache.list_system_killmails(system_id) do
          {:ok, killmail_ids} when is_list(killmail_ids) ->
            Logger.debug("[DEBUG] Found killmail IDs for system",
              system_id: system_id,
              killmail_ids: killmail_ids,
              count: length(killmail_ids)
            )

            result = get_enriched_killmails(killmail_ids, limit)

            Logger.debug("[DEBUG] Fetched enriched killmails",
              system_id: system_id,
              requested_count: length(killmail_ids),
              returned_count: length(result)
            )

            result

          {:error, %{type: :not_found}} ->
            # This is expected when no killmails passed validation (e.g., all too old)
            Logger.debug("[DEBUG] No killmails were cached for system (likely all filtered out)",
              system_id: system_id
            )

            []

          {:error, reason} ->
            # Only warn for actual errors, not expected "not found" cases
            Logger.warning("[WARNING] Failed to get cached killmail IDs after caching",
              system_id: system_id,
              error: reason
            )

            []
        end

      {:error, reason} ->
        Logger.warning("[WARNING] Failed to fetch fresh kills for preload",
          system_id: system_id,
          error: reason
        )

        []
    end
  end

  defp get_single_enriched_killmail(killmail_id) do
    result = Cache.get(:killmails, killmail_id)

    case result do
      {:ok, killmail} ->
        Logger.debug("[DEBUG] Successfully retrieved killmail from cache",
          killmail_id: killmail_id,
          has_kill_time: Map.has_key?(killmail, "kill_time"),
          kill_time: Map.get(killmail, "kill_time")
        )

      {:error, reason} ->
        Logger.debug("[DEBUG] Failed to retrieve killmail from cache",
          killmail_id: killmail_id,
          error: inspect(reason)
        )
    end

    result
  end

  defp maybe_filter_recent(kills, nil), do: kills

  defp maybe_filter_recent(kills, cutoff_time) do
    Enum.filter(kills, fn killmail ->
      # Convert map to struct if needed
      killmail_struct = ensure_killmail_struct(killmail)

      case killmail_struct do
        %Killmail{} = km -> killmail_recent?(km, cutoff_time)
        # Skip if conversion fails
        _ -> false
      end
    end)
  end

  defp kill_time_range([]), do: "no kills"

  defp kill_time_range(times) do
    "#{List.first(times)} to #{List.last(times)}"
  end

  defp log_sample_kill([]), do: :ok

  defp log_sample_kill([sample | _]) do
    # Convert to struct if needed
    case ensure_killmail_struct(sample) do
      %Killmail{} = killmail ->
        Logger.debug("[DEBUG] Sample kill data",
          killmail_id: killmail.killmail_id,
          victim_character: killmail.victim.character_name,
          victim_corp: killmail.victim.corporation_name,
          attacker_count: length(killmail.attackers),
          solar_system_id: killmail.system_id,
          total_value: killmail.zkb && killmail.zkb.total_value
        )

      _ ->
        Logger.debug("[DEBUG] Sample kill data (raw map)",
          data: inspect(sample, limit: 200)
        )
    end
  end
end
