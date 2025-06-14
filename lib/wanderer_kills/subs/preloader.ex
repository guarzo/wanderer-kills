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
  alias WandererKills.Ingest.Killmails.ZkbClient
  alias WandererKills.Core.Systems.KillmailProcessor

  @type system_id :: integer()
  @type killmail :: map()
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
    - List of enriched killmail maps
  """
  @spec preload_kills_for_system(system_id(), limit(), hours()) :: [killmail()]
  def preload_kills_for_system(system_id, limit, since_hours \\ 24) do
    Logger.info("📦 Preloading kills for system",
      system_id: system_id,
      limit: limit,
      since_hours: since_hours
    )

    result =
      case Cache.list_system_killmails(system_id) do
        {:ok, killmail_ids} when is_list(killmail_ids) and killmail_ids != [] ->
          Logger.info("📦 Found cached killmails, using cache",
            system_id: system_id,
            cached_count: length(killmail_ids)
          )

          get_enriched_killmails(killmail_ids, limit)

        _ ->
          Logger.info("📦 No cached killmails found, fetching fresh data",
            system_id: system_id
          )

          fetch_and_cache_fresh_kills(system_id, limit, since_hours)
      end

    Logger.info("📦 Preload completed",
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
    - List of enriched killmail maps
  """
  @spec get_enriched_killmails([integer()], limit(), boolean()) :: [killmail()]
  def get_enriched_killmails(killmail_ids, limit, filter_recent \\ true) do
    Logger.debug("📦 get_enriched_killmails called", %{
      killmail_ids_count: length(killmail_ids),
      limit: limit,
      filter_recent: filter_recent
    })

    # Only include kills from the last hour if filtering is enabled
    cutoff_time =
      if filter_recent do
        now = DateTime.utc_now()
        cutoff = DateTime.add(now, -1 * 60 * 60, :second)

        Logger.debug("📦 Calculated cutoff time for filtering", %{
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
          Logger.debug("📦 Retrieved killmail from cache", %{
            killmail_id: killmail["killmail_id"]
          })

          [killmail | acc]

        {:error, reason}, acc ->
          Logger.debug("📦 Failed to retrieve killmail from cache", %{
            error: inspect(reason)
          })

          acc
      end)

    Logger.debug("📦 Fetched kills before filtering",
      count: length(fetched_kills)
    )

    result =
      fetched_kills
      |> Enum.reverse()
      |> maybe_filter_recent(cutoff_time)
      |> Enum.take(limit)

    Logger.debug("📦 Final result after filtering",
      count: length(result)
    )

    result
  end

  @doc """
  Extracts kill times from a list of killmails.

  Handles both `kill_time` and legacy `killmail_time` fields.
  """
  @spec extract_kill_times([killmail()]) :: [String.t()]
  def extract_kill_times(kills) do
    Enum.map(kills, fn kill ->
      case kill do
        %{"kill_time" => time} when not is_nil(time) -> to_string(time)
        %{"killmail_time" => time} when not is_nil(time) -> to_string(time)
        _ -> "unknown"
      end
    end)
  end

  @doc """
  Counts how many kills have enriched data (character names).

  A kill is considered enriched if it has:
  - Victim character name, OR
  - At least one attacker with a character name
  """
  @spec count_enriched_kills([killmail()]) :: non_neg_integer()
  def count_enriched_kills(kills) do
    Enum.count(kills, fn kill ->
      victim_name = get_in(kill, ["victim", "character_name"])
      attackers = kill["attackers"] || []

      victim_name != nil or
        Enum.any?(attackers, fn attacker ->
          attacker["character_name"] != nil
        end)
    end)
  end

  @doc """
  Checks if a killmail is recent enough based on cutoff time.
  """
  @spec killmail_recent?(killmail(), DateTime.t()) :: boolean()
  def killmail_recent?(killmail, cutoff_time) do
    case killmail["kill_time"] do
      %DateTime{} = dt ->
        result = DateTime.compare(dt, cutoff_time) == :gt

        Logger.debug("📦 Checking if killmail is recent",
          killmail_id: killmail["killmail_id"],
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

            Logger.debug("📦 Checking if killmail is recent (parsed from string)",
              killmail_id: killmail["killmail_id"],
              kill_time_string: time_string,
              kill_time_parsed: DateTime.to_iso8601(dt),
              cutoff_time: DateTime.to_iso8601(cutoff_time),
              comparison_result: DateTime.compare(dt, cutoff_time),
              is_recent: result
            )

            result

          {:error, _} ->
            Logger.error("Failed to parse kill_time",
              killmail_id: killmail["killmail_id"],
              kill_time: time_string
            )

            false
        end

      nil ->
        Logger.error("Enriched killmail missing kill_time",
          killmail_id: killmail["killmail_id"],
          available_keys: Map.keys(killmail) |> Enum.sort()
        )

        false

      other ->
        Logger.error("Enriched killmail has invalid kill_time format",
          killmail_id: killmail["killmail_id"],
          kill_time_type: inspect(other),
          kill_time_value: inspect(other, limit: 100)
        )

        false
    end
  end

  @doc """
  Logs a summary of preloaded kills.
  """
  @spec log_preload_summary(map(), system_id(), [killmail()]) :: :ok
  def log_preload_summary(context, system_id, kills) do
    killmail_ids = Enum.map(kills, & &1["killmail_id"])
    kill_times = extract_kill_times(kills)
    enriched_count = count_enriched_kills(kills)

    Logger.debug(
      "📦 Preload summary",
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

  defp fetch_and_cache_fresh_kills(system_id, limit, since_hours) do
    Logger.info("📦 Fetching fresh kills from ZKillboard",
      system_id: system_id,
      limit: limit,
      since_hours: since_hours
    )

    case ZkbClient.fetch_system_killmails(system_id, 50, since_hours) do
      {:ok, fresh_kills} when is_list(fresh_kills) ->
        # Only process the number of kills we need for preload
        kills_to_cache = Enum.take(fresh_kills, limit)

        Logger.info("📦 Processing fresh kills through pipeline",
          system_id: system_id,
          fetched_count: length(fresh_kills),
          processing_count: length(kills_to_cache)
        )

        # Cache the kills through the pipeline
        KillmailProcessor.process_system_killmails(system_id, kills_to_cache)

        Logger.info("📦 Fresh kills cached successfully",
          system_id: system_id,
          cached_count: length(kills_to_cache)
        )

        # Now get the enriched killmails from cache
        case Cache.list_system_killmails(system_id) do
          {:ok, killmail_ids} when is_list(killmail_ids) ->
            Logger.debug("📦 Found killmail IDs for system",
              system_id: system_id,
              killmail_ids: killmail_ids,
              count: length(killmail_ids)
            )

            result = get_enriched_killmails(killmail_ids, limit)

            Logger.debug("📦 Fetched enriched killmails",
              system_id: system_id,
              requested_count: length(killmail_ids),
              returned_count: length(result)
            )

            result

          {:error, %{type: :not_found}} ->
            # This is expected when no killmails passed validation (e.g., all too old)
            Logger.debug("📦 No killmails were cached for system (likely all filtered out)",
              system_id: system_id
            )

            []

          {:error, reason} ->
            # Only warn for actual errors, not expected "not found" cases
            Logger.warning("📦 Failed to get cached killmail IDs after caching",
              system_id: system_id,
              error: reason
            )

            []
        end

      {:error, reason} ->
        Logger.warning("📦 Failed to fetch fresh kills for preload",
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
        Logger.debug("📦 Successfully retrieved killmail from cache",
          killmail_id: killmail_id,
          has_kill_time: Map.has_key?(killmail, "kill_time"),
          kill_time: Map.get(killmail, "kill_time")
        )

      {:error, reason} ->
        Logger.debug("📦 Failed to retrieve killmail from cache",
          killmail_id: killmail_id,
          error: inspect(reason)
        )
    end

    result
  end

  defp maybe_filter_recent(kills, nil), do: kills

  defp maybe_filter_recent(kills, cutoff_time) do
    Enum.filter(kills, fn killmail ->
      killmail_recent?(killmail, cutoff_time)
    end)
  end

  defp kill_time_range([]), do: "no kills"

  defp kill_time_range(times) do
    "#{List.first(times)} to #{List.last(times)}"
  end

  defp log_sample_kill([]), do: :ok

  defp log_sample_kill([sample | _]) do
    Logger.debug("📦 Sample kill data",
      killmail_id: sample["killmail_id"],
      victim_character: get_in(sample, ["victim", "character_name"]),
      victim_corp: get_in(sample, ["victim", "corporation_name"]),
      attacker_count: length(sample["attackers"] || []),
      solar_system_id: sample["solar_system_id"],
      total_value: sample["total_value"]
    )
  end
end
