defmodule WandererKills.Parser.Core do
  @moduledoc """
  Core functionality for parsing killmails from zKillboard.
  """

  require Logger
  alias WandererKills.Parser.{CacheHandler, Stats, Flatten}
  alias WandererKills.Core.Clock
  alias WandererKills.Cache.Unified, as: Cache
  alias WandererKills.Config

  @type raw_km :: map()
  @type merged_km :: map()
  @type result_ok :: {:ok, map()}
  @type result_error :: {:error, :invalid_payload | :missing_kill_time}
  @type result_t :: result_ok() | :older | result_error()
  @type killmail :: %{
          id: integer(),
          system_id: integer(),
          timestamp: DateTime.t(),
          victim: map(),
          attackers: [map()],
          items: [map()]
        }

  @doc """
  Parses a killmail from zKillboard.
  """
  @spec parse_killmail(raw_km()) :: {:ok, map()} | :older | {:error, term()}
  def parse_killmail(killmail) do
    cutoff = get_cutoff_time()

    case build_kill_data(killmail, cutoff) do
      {:ok, kill_data} ->
        case CacheHandler.store_killmail(kill_data) do
          :ok ->
            Stats.increment_stored()
            {:ok, kill_data}
        end

      :older ->
        Logger.debug("[Parser] Skipping older killmail")
        Stats.increment_skipped()
        :older

      {:error, reason} ->
        Logger.error("[Parser] Failed to build killmail data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Parses a list of killmails from zKillboard.
  """
  @spec parse_killmails([raw_km()]) :: {:ok, [map()]} | {:partial, [map()], [result_error()]}
  def parse_killmails(killmails) when is_list(killmails) do
    results = Enum.map(killmails, &parse_killmail/1)
    {successful, failed} = Enum.split_with(results, &match?({:ok, _}, &1))
    successful_killmails = Enum.map(successful, fn {:ok, km} -> km end)

    case failed do
      [] -> {:ok, successful_killmails}
      errors -> {:partial, successful_killmails, errors}
    end
  end

  @doc """
  Merge full ESI killmail data with its zKB partial payload.
  Validates that kill_time is present in the data.
  """
  @spec merge_killmail_data(raw_km(), raw_km()) :: {:ok, merged_km()} | result_error()
  def merge_killmail_data(%{"killmail_id" => id} = full, %{"zkb" => zkb})
      when is_integer(id) and is_map(zkb) do
    kill_time = Map.get(full, "kill_time") || Map.get(full, "killmail_time")

    if kill_time do
      merged =
        full
        |> Map.put("zkb", zkb)
        |> Map.put("kill_time", kill_time)

      {:ok, merged}
    else
      {:error, :missing_kill_time}
    end
  end

  def merge_killmail_data(_, _), do: {:error, :invalid_payload}

  @doc """
  Given merged data and a cutoff, either build the final map, or return `:older` if it's too old.
  """
  @spec build_kill_data(merged_km(), DateTime.t()) :: result_t()
  def build_kill_data(%{"kill_time" => _} = merged, %DateTime{} = cutoff) do
    with {:ok, kill_time} <- get_kill_time(merged) do
      if DateTime.compare(kill_time, cutoff) == :lt do
        Logger.debug(
          "[Parser] Skipping killmail #{merged["killID"]} - Kill time: #{DateTime.to_iso8601(kill_time)}, Cutoff: #{DateTime.to_iso8601(cutoff)}"
        )

        Stats.increment_skipped()
        :older
      else
        do_build(Map.put(merged, "kill_time", kill_time))
      end
    end
  end

  def build_kill_data(_, _), do: {:error, :invalid_payload}

  @doc """
  Gets the kill time from a killmail.

  ## Parameters
  - `killmail` - The killmail data

  ## Returns
  - `{:ok, DateTime.t()}` - On successful parsing
  - `{:error, reason}` - On failure
  """
  @spec get_kill_time(merged_km()) :: {:ok, DateTime.t()} | {:error, term()}
  def get_kill_time(%{"killmail_time" => time}) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> {:ok, dt}
      error -> error
    end
  end

  def get_kill_time(_), do: {:error, :invalid_time}

  # The real builder, matching on all required fields:
  @spec do_build(merged_km()) :: result_t()
  defp do_build(%{
         "killmail_id" => id,
         "kill_time" => %DateTime{} = ts,
         "solar_system_id" => sys,
         "victim" => victim_map,
         "attackers" => attackers,
         "zkb" => zkb
       })
       when is_map(victim_map) and is_list(attackers) do
    try do
      with {:ok, killmail_data} <- extract_killmail_data(id, ts, sys, victim_map, attackers, zkb),
           {:ok, built} <- build_final_map(killmail_data) do
        {:ok, built}
      else
        {:error, reason} ->
          Logger.error("[Core] Failed to build killmail #{id}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("[Core] Error building killmail #{id}: #{inspect(e)}")
        {:error, :build_error}
    end
  end

  defp do_build(%{"killmail_id" => id}) do
    Logger.error("[Core] Invalid killmail data for build: #{id}")
    {:error, :invalid_payload}
  end

  defp do_build(_) do
    Logger.error("[Core] Invalid killmail data: missing killmail_id")
    {:error, :invalid_payload}
  end

  # Extract all required data into a structured format
  @spec extract_killmail_data(integer(), DateTime.t(), integer(), map(), list(), map()) ::
          {:ok, WandererKills.Schema.Killmail.t()} | {:error, term()}
  defp extract_killmail_data(id, ts, sys, victim_map, attackers, zkb) do
    with {:ok, victim} <- get_victim(victim_map),
         {:ok, attackers} <- get_attackers(attackers),
         {:ok, system_id} <- get_system_id(sys),
         {:ok, time} <- get_time(ts) do
      final_blow = Enum.find(attackers, & &1["final_blow"])

      data = %WandererKills.Schema.Killmail{
        killmail_id: id,
        kill_time: time,
        solar_system_id: system_id,
        attacker_count: length(attackers),
        total_value: Map.get(zkb, "totalValue", 0),
        npc: Map.get(zkb, "npc", false),
        victim: victim,
        attackers: attackers,
        zkb: zkb,
        final_blow: final_blow
      }

      {:ok, data}
    end
  end

  # Build the final map from the structured data
  @spec build_final_map(WandererKills.Schema.Killmail.t()) :: {:ok, map()} | {:error, term()}
  defp build_final_map(%WandererKills.Schema.Killmail{} = data) do
    built =
      %{
        "killmail_id" => data.killmail_id,
        "kill_time" => data.kill_time,
        "solar_system_id" => data.solar_system_id,
        "attacker_count" => data.attacker_count,
        "total_value" => data.total_value,
        "npc" => data.npc,
        "victim" => data.victim,
        "attackers" => data.attackers,
        "zkb" => data.zkb
      }
      |> Map.merge(Flatten.flatten_fields(data.victim, "victim"))
      |> maybe_flatten_final_blow(data.final_blow)

    {:ok, built}
  end

  @spec maybe_flatten_final_blow(map(), map() | nil) :: map()
  defp maybe_flatten_final_blow(built_map, nil), do: built_map

  defp maybe_flatten_final_blow(built_map, %{} = fb_map) do
    built_map
    |> Map.put("final_blow", fb_map)
    |> Map.merge(Flatten.flatten_fields(fb_map, "final_blow"))
  end

  # Helper functions for extracting fields
  @spec get_victim(map()) :: {:ok, map()} | {:error, term()}
  defp get_victim(%{"ship_type_id" => _} = victim), do: {:ok, victim}
  defp get_victim(_), do: {:error, :invalid_victim}

  @spec get_attackers(list()) :: {:ok, list()} | {:error, term()}
  defp get_attackers(attackers) when is_list(attackers) and length(attackers) > 0 do
    {:ok, attackers}
  end

  defp get_attackers(_), do: {:error, :invalid_attackers}

  @spec get_system_id(integer()) :: {:ok, integer()} | {:error, term()}
  defp get_system_id(id) when is_integer(id), do: {:ok, id}
  defp get_system_id(_), do: {:error, :invalid_system_id}

  @spec get_time(DateTime.t()) :: {:ok, DateTime.t()} | {:error, term()}
  # Only match if input is a DateTime struct
  defp get_time(dt) when is_struct(dt, DateTime), do: {:ok, dt}
  defp get_time(_), do: {:error, :invalid_time}

  @doc """
  Gets the cutoff time for killmails.
  """
  @spec get_cutoff_time() :: DateTime.t()
  def get_cutoff_time do
    cutoff_seconds = Config.parser().cutoff_seconds
    Clock.seconds_ago(cutoff_seconds)
  end

  @doc """
  Parse killmails until we encounter one older than the cutoff time.

  This function provides unified parsing logic that can be used by both
  fetcher modules while maintaining consistent behavior.

  ## Parameters
  - `raw_killmails` - List of raw killmail data from the API
  - `cutoff` - DateTime cutoff for filtering old killmails
  - `caller` - The calling module for consistent logging

  ## Returns
  List of parsed killmails (may be empty if all are too old)
  """
  @spec parse_until_older([map()], DateTime.t(), atom()) :: [killmail()]
  def parse_until_older(raw_killmails, cutoff, caller) do
    do_parse_until_older(raw_killmails, cutoff, caller, [])
  end

  @spec do_parse_until_older([map()], DateTime.t(), atom(), [killmail()]) :: [killmail()]
  defp do_parse_until_older([], _cutoff, _caller, acc), do: Enum.reverse(acc)

  defp do_parse_until_older([raw | rest], cutoff, caller, acc) do
    # Convert the data format to match what the parser expects
    killmail = %{
      "killID" => raw["killmail_id"],
      "killmail_id" => raw["killmail_id"],
      "killmail_time" => raw["killmail_time"],
      "solar_system_id" => raw["solar_system_id"],
      "victim" => raw["victim"],
      "attackers" => raw["attackers"],
      "zkb" => %{
        "hash" => raw["zkb"]["hash"],
        "locationID" => raw["solar_system_id"],
        "fittedValue" => raw["zkb"]["totalValue"],
        "totalValue" => raw["zkb"]["totalValue"],
        "points" => 1,
        "npc" => false,
        "solo" => false,
        "awox" => false
      }
    }

    case parse_partial(killmail, cutoff) do
      {:error, reason} ->
        Logger.warning("[Parser] Failed to parse killmail: #{inspect(reason)}")
        do_parse_until_older(rest, cutoff, caller, acc)

      {:ok, parsed} when is_map(parsed) ->
        # Ensure we preserve the original killmail_id
        parsed = Map.put(parsed, "killmail_id", raw["killmail_id"])
        # Cache the killmail after successful parsing
        Cache.set_killmail(parsed["killmail_id"], parsed)
        do_parse_until_older(rest, cutoff, caller, [parsed | acc])
    end
  end

  @doc """
  Parse a partial killmail, handling missing or incomplete data.

  ## Parameters
  - `killmail` - The killmail data to parse
  - `cutoff` - DateTime cutoff for filtering old killmails

  ## Returns
  - `{:ok, parsed_killmail}` - On successful parsing
  - `{:error, reason}` - On failure
  """
  @spec parse_partial(merged_km(), DateTime.t()) :: {:ok, killmail()} | {:error, term()}
  def parse_partial(killmail, cutoff) do
    with {:ok, time} <- get_kill_time(killmail),
         :ok <- validate_time(time, cutoff),
         killmail_with_time = Map.put(killmail, "kill_time", time),
         {:ok, parsed} <- do_build(killmail_with_time) do
      {:ok, parsed}
    else
      {:error, :too_old} -> {:error, :too_old}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec validate_time(DateTime.t(), DateTime.t()) :: :ok | {:error, :too_old}
  defp validate_time(time, cutoff) do
    if DateTime.compare(time, cutoff) == :lt do
      {:error, :too_old}
    else
      :ok
    end
  end
end
