defmodule WandererKills.Killmails.Parser do
  @moduledoc """
  Core killmail parsing functionality with a focused API.

  This module provides the essential killmail parsing operations while keeping
  internal implementation details private. It follows a consistent naming
  convention and minimizes the public API surface.

  ## Public API

  - `parse_full_killmail/2` - Parse a complete killmail with zkb data
  - `parse_partial_killmail/2` - Parse a partial killmail, fetching full data
  - `merge_killmail_data/2` - Merge ESI and zKB data
  - `validate_killmail_time/1` - Validate killmail timestamp

  ## Usage

  ```elixir
  # Parse a complete killmail
  {:ok, parsed} = KillmailParser.parse_full_killmail(killmail, cutoff_time)

  # Parse a partial killmail
  {:ok, parsed} = KillmailParser.parse_partial_killmail(partial, cutoff_time)

  # Merge ESI and zKB data
  {:ok, merged} = KillmailParser.merge_killmail_data(esi_data, zkb_data)
  ```

  ## Error Handling

  All functions return standardized results:
  - `{:ok, result}` - On success
  - `{:ok, :kill_older}` - When killmail is older than cutoff
  - `{:error, reason}` - On failure
  """

  require Logger

  alias WandererKills.Killmails.{Enricher, Cache}
  alias WandererKills.Observability.Monitoring
  alias WandererKills.Infrastructure.Error

  @type killmail :: map()
  @type raw_killmail :: map()
  @type merged_killmail :: map()
  @type parse_result :: {:ok, killmail()} | {:ok, :kill_older} | {:error, term()}

  @doc """
  Parses a complete killmail with zkb data.

  This is the main entry point for parsing killmails when you have both
  the full ESI data and zKB metadata.

  ## Parameters
  - `killmail` - The merged killmail data (ESI + zKB)
  - `cutoff_time` - DateTime cutoff for filtering old killmails

  ## Returns
  - `{:ok, parsed_killmail}` - On successful parsing
  - `{:ok, :kill_older}` - When killmail is older than cutoff
  - `{:error, reason}` - On failure
  """
  @spec parse_full_killmail(killmail(), DateTime.t()) :: parse_result()
  def parse_full_killmail(killmail, cutoff_time) when is_map(killmail) do
    killmail_id = get_killmail_id(killmail)

    Logger.debug("Parsing full killmail",
      killmail_id: killmail_id,
      has_solar_system_id: Map.has_key?(killmail, "solar_system_id"),
      has_victim: Map.has_key?(killmail, "victim"),
      has_attackers: Map.has_key?(killmail, "attackers"),
      has_zkb: Map.has_key?(killmail, "zkb"),
      killmail_keys: Map.keys(killmail) |> Enum.sort()
    )

    with {:ok, validated} <- validate_killmail_structure(killmail),
         {:ok, time_checked} <- check_killmail_time(validated, cutoff_time),
         {:ok, built} <- build_killmail_data(time_checked),
         {:ok, enriched} <- enrich_killmail_data(built) do
      Monitoring.increment_stored()
      {:ok, enriched}
    else
      {:error, %Error{type: :kill_too_old}} ->
        Monitoring.increment_skipped()
        {:ok, :kill_older}

      {:error, reason} ->
        Logger.error("Failed to parse killmail",
          killmail_id: get_killmail_id(killmail),
          error: reason,
          step: determine_failure_step(reason),
          killmail_sample: inspect(killmail, limit: 3, printable_limit: 100)
        )

        {:error, reason}
    end
  end

  @doc """
  Parses a partial killmail by fetching full data from ESI.

  ## Parameters
  - `partial` - The partial killmail data with zKB metadata
  - `cutoff_time` - DateTime cutoff for filtering old killmails

  ## Returns
  - `{:ok, parsed_killmail}` - On successful parsing
  - `{:ok, :kill_older}` - When killmail is older than cutoff
  - `{:error, reason}` - On failure
  """
  @spec parse_partial_killmail(raw_killmail(), DateTime.t()) :: parse_result()
  def parse_partial_killmail(%{"killID" => id, "zkb" => zkb} = partial, cutoff_time) do
    Logger.debug("Parsing partial killmail", killmail_id: id)

    with {:ok, full_data} <- fetch_full_killmail(id, zkb),
         {:ok, merged} <- merge_killmail_data(full_data, partial) do
      parse_full_killmail(merged, cutoff_time)
    else
      {:error, reason} ->
        Logger.error("Failed to parse partial killmail", killmail_id: id, error: reason)
        {:error, reason}
    end
  end

  def parse_partial_killmail(_, _),
    do:
      {:error,
       Error.killmail_error(
         :invalid_partial_format,
         "Partial killmail must have killID and zkb fields"
       )}

  @doc """
  Merges ESI killmail data with zKB metadata.

  ## Parameters
  - `esi_data` - Full killmail data from ESI
  - `zkb_data` - Partial data with zKB metadata

  ## Returns
  - `{:ok, merged_killmail}` - On successful merge
  - `{:error, reason}` - On failure
  """
  @spec merge_killmail_data(killmail(), raw_killmail()) ::
          {:ok, merged_killmail()} | {:error, term()}
  def merge_killmail_data(%{"killmail_id" => id} = esi_data, %{"zkb" => zkb})
      when is_integer(id) and is_map(zkb) do
    kill_time = get_kill_time_field(esi_data)

    if kill_time do
      merged =
        esi_data
        |> Map.put("zkb", zkb)
        |> Map.put("kill_time", kill_time)

      {:ok, merged}
    else
      {:error, Error.killmail_error(:missing_kill_time, "Kill time not found in ESI data")}
    end
  end

  def merge_killmail_data(_, _),
    do:
      {:error,
       Error.killmail_error(:invalid_merge_data, "Invalid data format for merge operation")}

  @doc """
  Validates killmail timestamp and parses it.

  ## Parameters
  - `killmail` - Killmail data containing time information

  ## Returns
  - `{:ok, datetime}` - On successful parsing
  - `{:error, reason}` - On failure
  """
  @spec validate_killmail_time(killmail()) :: {:ok, DateTime.t()} | {:error, term()}
  def validate_killmail_time(%{"killmail_time" => time}) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} ->
        {:ok, dt}

      {:error, reason} ->
        {:error,
         Error.killmail_error(:invalid_time_format, "Failed to parse ISO8601 timestamp", false, %{
           underlying_error: reason
         })}
    end
  end

  def validate_killmail_time(%{"kill_time" => time}) when is_binary(time) do
    validate_killmail_time(%{"killmail_time" => time})
  end

  def validate_killmail_time(_),
    do: {:error, Error.killmail_error(:missing_kill_time, "Killmail missing valid time field")}

  # Private functions for internal implementation

  @spec get_killmail_id(killmail()) :: integer() | nil
  defp get_killmail_id(%{"killmail_id" => id}) when is_integer(id), do: id
  defp get_killmail_id(%{"killID" => id}) when is_integer(id), do: id
  defp get_killmail_id(_), do: nil

  @spec validate_killmail_structure(killmail()) :: {:ok, killmail()} | {:error, term()}
  defp validate_killmail_structure(%{"killmail_id" => id} = killmail) when is_integer(id) do
    required_fields = ["solar_system_id", "victim", "attackers"]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(killmail, &1))

    if Enum.empty?(missing_fields) do
      {:ok, killmail}
    else
      Logger.error("[Parser] Killmail structure validation failed",
        killmail_id: id,
        required_fields: required_fields,
        missing_fields: missing_fields,
        available_keys: Map.keys(killmail),
        killmail_sample: killmail |> inspect(limit: 5, printable_limit: 200)
      )

      {:error,
       Error.killmail_error(
         :missing_required_fields,
         "Killmail missing required ESI fields",
         false,
         %{
           missing_fields: missing_fields,
           required_fields: required_fields
         }
       )}
    end
  end

  defp validate_killmail_structure(killmail) when is_map(killmail) do
    Logger.error("[Parser] Killmail missing killmail_id field",
      available_keys: Map.keys(killmail),
      killmail_sample: killmail |> inspect(limit: 5, printable_limit: 200)
    )

    {:error, Error.killmail_error(:missing_killmail_id, "Killmail missing killmail_id field")}
  end

  @spec determine_failure_step(term()) :: String.t()
  defp determine_failure_step(%Error{type: :missing_required_fields}), do: "structure_validation"
  defp determine_failure_step(%Error{type: :missing_killmail_id}), do: "structure_validation"
  defp determine_failure_step(%Error{type: :invalid_time_format}), do: "time_validation"
  defp determine_failure_step(%Error{type: :missing_kill_time}), do: "time_validation"
  defp determine_failure_step(%Error{type: :kill_too_old}), do: "time_check"
  defp determine_failure_step(%Error{type: :build_failed}), do: "data_building"
  defp determine_failure_step(_), do: "unknown"

  @spec check_killmail_time(killmail(), DateTime.t()) :: {:ok, killmail()} | {:error, Error.t()}
  defp check_killmail_time(killmail, cutoff_time) do
    case validate_killmail_time(killmail) do
      {:ok, kill_time} ->
        if DateTime.compare(kill_time, cutoff_time) == :lt do
          Logger.debug("Killmail is older than cutoff",
            killmail_id: get_killmail_id(killmail),
            kill_time: DateTime.to_iso8601(kill_time),
            cutoff: DateTime.to_iso8601(cutoff_time)
          )

          {:error,
           Error.killmail_error(:kill_too_old, "Killmail is older than cutoff time", false, %{
             kill_time: DateTime.to_iso8601(kill_time),
             cutoff: DateTime.to_iso8601(cutoff_time)
           })}
        else
          {:ok, Map.put(killmail, "parsed_kill_time", kill_time)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec build_killmail_data(killmail()) :: {:ok, killmail()} | {:error, term()}
  defp build_killmail_data(killmail) do
    # Extract and structure the core killmail data
    try do
      structured = %{
        "killmail_id" => killmail["killmail_id"],
        "kill_time" => killmail["parsed_kill_time"],
        "solar_system_id" => killmail["solar_system_id"],
        "victim" => normalize_victim_data(killmail["victim"]),
        "attackers" => normalize_attackers_data(killmail["attackers"]),
        "zkb" => killmail["zkb"] || %{},
        "total_value" => get_in(killmail, ["zkb", "totalValue"]) || 0,
        "npc" => get_in(killmail, ["zkb", "npc"]) || false
      }

      {:ok, structured}
    rescue
      error ->
        Logger.error("Failed to build killmail data", error: inspect(error))

        {:error,
         Error.killmail_error(:build_failed, "Failed to build killmail data structure", false, %{
           exception: inspect(error)
         })}
    end
  end

  @spec enrich_killmail_data(killmail()) :: {:ok, killmail()} | {:error, term()}
  defp enrich_killmail_data(killmail) do
    case Enricher.enrich_killmail(killmail) do
      {:ok, enriched} ->
        # Store in cache after successful enrichment
        Cache.store_killmail(enriched)
        {:ok, enriched}

      {:error, reason} ->
        Logger.warning("Failed to enrich killmail, using basic data",
          killmail_id: killmail["killmail_id"],
          error: reason
        )

        # Store basic data even if enrichment fails
        Cache.store_killmail(killmail)
        {:ok, killmail}
    end
  end

  @spec fetch_full_killmail(integer(), map()) :: {:ok, killmail()} | {:error, term()}
  defp fetch_full_killmail(killmail_id, zkb) do
    hash = zkb["hash"]

    # Try to get from cache first, then fetch from ESI if needed
    case Cache.get_killmail(killmail_id) do
      {:ok, full_data} ->
        {:ok, full_data}

      {:error, :not_found} ->
        # Fetch full killmail data from ESI
        case WandererKills.External.ESI.Client.get_killmail(killmail_id, hash) do
          {:ok, esi_data} when is_map(esi_data) ->
            # Cache the result
            Cache.store_killmail(esi_data)
            {:ok, esi_data}

          {:error, reason} ->
            Logger.error("Failed to fetch full killmail from ESI",
              killmail_id: killmail_id,
              hash: hash,
              error: reason
            )

            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get_kill_time_field(killmail()) :: String.t() | nil
  defp get_kill_time_field(killmail) do
    killmail["kill_time"] || killmail["killmail_time"]
  end

  @spec normalize_victim_data(map()) :: map()
  defp normalize_victim_data(victim) when is_map(victim) do
    %{
      "character_id" => victim["character_id"],
      "corporation_id" => victim["corporation_id"],
      "alliance_id" => victim["alliance_id"],
      "ship_type_id" => victim["ship_type_id"],
      "damage_taken" => victim["damage_taken"],
      "items" => victim["items"] || []
    }
  end

  @spec normalize_attackers_data([map()]) :: [map()]
  defp normalize_attackers_data(attackers) when is_list(attackers) do
    Enum.map(attackers, fn attacker ->
      %{
        "character_id" => attacker["character_id"],
        "corporation_id" => attacker["corporation_id"],
        "alliance_id" => attacker["alliance_id"],
        "ship_type_id" => attacker["ship_type_id"],
        "weapon_type_id" => attacker["weapon_type_id"],
        "damage_done" => attacker["damage_done"],
        "final_blow" => attacker["final_blow"] || false,
        "security_status" => attacker["security_status"]
      }
    end)
  end
end
