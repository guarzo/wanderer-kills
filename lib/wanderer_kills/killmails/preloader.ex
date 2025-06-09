defmodule WandererKills.Killmails.Preloader do
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
  
  alias WandererKills.Cache.Helper
  alias WandererKills.Killmails.ZkbClient
  alias WandererKills.Systems.KillmailManager

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
    case Helper.get_system_killmails(system_id) do
      {:ok, killmail_ids} when is_list(killmail_ids) and killmail_ids != [] ->
        fetch_enriched_killmails(killmail_ids, limit)

      _ ->
        fetch_and_cache_fresh_kills(system_id, limit, since_hours)
    end
  end

  @doc """
  Fetches enriched killmails from cache by their IDs.
  
  ## Parameters
    - `killmail_ids` - List of killmail IDs to fetch
    - `limit` - Maximum number of kills to return
    - `filter_recent` - Whether to filter by recency (default: true)
    
  ## Returns
    - List of enriched killmail maps
  """
  @spec fetch_enriched_killmails([integer()], limit(), boolean()) :: [killmail()]
  def fetch_enriched_killmails(killmail_ids, limit, filter_recent \\ true) do
    # Only include kills from the last hour if filtering is enabled
    cutoff_time = if filter_recent do
      DateTime.utc_now() |> DateTime.add(-1 * 60 * 60, :second)
    else
      nil
    end
    
    killmail_ids
    |> Enum.take(limit * 2)  # Take more to account for filtering
    |> Enum.map(&get_single_enriched_killmail/1)
    |> Enum.reduce([], fn
      {:ok, killmail}, acc -> [killmail | acc]
      {:error, _}, acc -> acc
    end)
    |> Enum.reverse()
    |> maybe_filter_recent(cutoff_time)
    |> Enum.take(limit)
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
        DateTime.compare(dt, cutoff_time) == :gt
        
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

    Logger.info("📦 Preload summary",
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
    Logger.info("📦 No cached kills found, fetching fresh kills",
      system_id: system_id,
      limit: limit,
      since_hours: since_hours
    )

    case ZkbClient.fetch_system_killmails(system_id, 50, since_hours) do
      {:ok, fresh_kills} when is_list(fresh_kills) ->
        # Only process the number of kills we need for preload
        kills_to_cache = Enum.take(fresh_kills, limit)
        
        # Cache the kills through the pipeline
        KillmailManager.process_system_killmails(system_id, kills_to_cache)

        Logger.info("📦 Fetched and cached fresh kills",
          system_id: system_id,
          fresh_kills_fetched: length(fresh_kills),
          kills_to_process: length(kills_to_cache)
        )

        # Now get the enriched killmails from cache
        case Helper.get_system_killmails(system_id) do
          {:ok, killmail_ids} when is_list(killmail_ids) ->
            fetch_enriched_killmails(killmail_ids, limit)

          {:error, _reason} ->
            Logger.warning("📦 Failed to get cached killmail IDs after caching",
              system_id: system_id
            )
            []
        end

      {:error, reason} ->
        Logger.info("📦 Failed to fetch fresh kills for preload",
          system_id: system_id,
          error: reason
        )
        []
    end
  end

  defp get_single_enriched_killmail(killmail_id) do
    Helper.get(:killmails, killmail_id)
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
    Logger.info("📦 Sample kill data",
      killmail_id: sample["killmail_id"],
      victim_character: get_in(sample, ["victim", "character_name"]),
      victim_corp: get_in(sample, ["victim", "corporation_name"]),
      attacker_count: length(sample["attackers"] || []),
      solar_system_id: sample["solar_system_id"],
      total_value: sample["total_value"]
    )
  end
end