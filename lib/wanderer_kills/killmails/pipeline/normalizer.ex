defmodule WandererKills.Killmails.Pipeline.Normalizer do
  @moduledoc """
  Data normalization functions for killmail processing.
  
  This module handles normalizing victim and attacker data structures
  to ensure consistent formatting throughout the pipeline.
  """
  
  @type killmail :: map()
  
  @doc """
  Normalizes victim data structure.
  
  Ensures all expected fields are present with appropriate defaults.
  """
  @spec normalize_victim(map()) :: map()
  def normalize_victim(victim) when is_map(victim) do
    %{
      "character_id" => victim["character_id"],
      "corporation_id" => victim["corporation_id"],
      "alliance_id" => victim["alliance_id"],
      "ship_type_id" => victim["ship_type_id"],
      "damage_taken" => victim["damage_taken"],
      "items" => victim["items"] || []
    }
  end
  
  @doc """
  Normalizes a list of attackers.
  
  Ensures all attackers have consistent field structure.
  """
  @spec normalize_attackers([map()]) :: [map()]
  def normalize_attackers(attackers) when is_list(attackers) do
    Enum.map(attackers, &normalize_attacker/1)
  end
  
  @doc """
  Normalizes a single attacker's data.
  """
  @spec normalize_attacker(map()) :: map()
  def normalize_attacker(attacker) when is_map(attacker) do
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
  end
  
  @doc """
  Extracts the kill time field from a killmail.
  
  Handles different field name variations.
  """
  @spec get_kill_time(killmail()) :: String.t() | nil
  def get_kill_time(killmail) do
    killmail["kill_time"]
  end
  
  @doc """
  Extracts the killmail ID from a killmail.
  """
  @spec get_killmail_id(killmail()) :: integer() | nil
  def get_killmail_id(%{"killmail_id" => id}) when is_integer(id), do: id
  def get_killmail_id(_), do: nil
end