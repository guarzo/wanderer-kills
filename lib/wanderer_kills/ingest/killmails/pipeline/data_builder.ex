defmodule WandererKills.Ingest.Killmails.Pipeline.DataBuilder do
  @moduledoc """
  Builds structured killmail data from normalized inputs.

  This module is responsible for assembling the final killmail
  data structure with all required fields properly formatted.
  """

  require Logger
  alias WandererKills.Core.Support.Error
  alias WandererKills.Ingest.Killmails.Transformations

  @type killmail :: map()

  @doc """
  Builds the structured killmail data.

  Takes a validated killmail and creates the final structured format
  with normalized victim and attacker data.
  """
  @spec build_killmail_data(killmail()) :: {:ok, killmail()} | {:error, Error.t()}
  def build_killmail_data(killmail) do
    # Trust normalized keys from earlier pipeline stage
    structured = %{
      "killmail_id" => killmail["killmail_id"],
      "kill_time" => killmail["kill_time"],
      "system_id" => killmail["system_id"],
      "victim" => Transformations.normalize_victim(killmail["victim"]),
      "attackers" => Transformations.normalize_attackers(killmail["attackers"]),
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

  @doc """
  Merges ESI killmail data with zKB metadata.

  Combines the full ESI data with zkillboard metadata to create
  a complete killmail record.
  """
  @spec merge_killmail_data(map(), map()) :: {:ok, map()} | {:error, Error.t()}
  def merge_killmail_data(%{"killmail_id" => id} = esi_data, %{"zkb" => zkb})
      when is_integer(id) and is_map(zkb) do
    case Transformations.get_killmail_time(esi_data) || esi_data["kill_time"] do
      kill_time when is_binary(kill_time) ->
        merged =
          esi_data
          |> Map.put("zkb", zkb)
          |> Map.put("kill_time", kill_time)

        {:ok, merged}

      nil ->
        {:error, Error.killmail_error(:missing_kill_time, "Killmail time not found in ESI data")}
    end
  end

  def merge_killmail_data(_, _),
    do:
      {:error,
       Error.killmail_error(:invalid_merge_data, "Invalid data format for merge operation")}
end
