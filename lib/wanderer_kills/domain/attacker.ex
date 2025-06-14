defmodule WandererKills.Domain.Attacker do
  @moduledoc """
  Domain struct representing a killmail attacker.
  """

  @type t :: %__MODULE__{
          character_id: integer() | nil,
          corporation_id: integer() | nil,
          alliance_id: integer() | nil,
          ship_type_id: integer() | nil,
          weapon_type_id: integer() | nil,
          damage_done: integer(),
          final_blow: boolean(),
          security_status: float(),
          # Enriched fields
          character_name: String.t() | nil,
          corporation_name: String.t() | nil,
          corporation_ticker: String.t() | nil,
          alliance_name: String.t() | nil,
          alliance_ticker: String.t() | nil,
          ship_name: String.t() | nil
        }

  defstruct [
    :character_id,
    :corporation_id,
    :alliance_id,
    :ship_type_id,
    :weapon_type_id,
    :damage_done,
    :final_blow,
    :security_status,
    # Enriched fields
    :character_name,
    :corporation_name,
    :corporation_ticker,
    :alliance_name,
    :alliance_ticker,
    :ship_name
  ]

  @doc """
  Creates a new Attacker struct from a map.

  ## Parameters
    - `attrs` - Map with attacker attributes

  ## Returns
    - `{:ok, %Attacker{}}` - Successfully created attacker
    - `{:error, reason}` - Failed to create attacker
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    attacker = %__MODULE__{
      character_id: get_field(attrs, ["character_id", :character_id]),
      corporation_id: get_field(attrs, ["corporation_id", :corporation_id]),
      alliance_id: get_field(attrs, ["alliance_id", :alliance_id]),
      ship_type_id: get_field(attrs, ["ship_type_id", :ship_type_id]),
      weapon_type_id: get_field(attrs, ["weapon_type_id", :weapon_type_id]),
      damage_done: get_field(attrs, ["damage_done", :damage_done]) || 0,
      final_blow: get_field(attrs, ["final_blow", :final_blow]) || false,
      security_status: get_field(attrs, ["security_status", :security_status]) || 0.0,
      # Check for pre-enriched fields
      character_name: get_field(attrs, ["character_name", :character_name, "attacker_name"]),
      corporation_name: get_field(attrs, ["corporation_name", :corporation_name]),
      corporation_ticker: get_field(attrs, ["corporation_ticker", :corporation_ticker]),
      alliance_name: get_field(attrs, ["alliance_name", :alliance_name]),
      alliance_ticker: get_field(attrs, ["alliance_ticker", :alliance_ticker]),
      ship_name: get_field(attrs, ["ship_name", :ship_name])
    }

    {:ok, attacker}
  end

  @doc """
  Converts an Attacker struct to a map for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = attacker) do
    %{
      "character_id" => attacker.character_id,
      "corporation_id" => attacker.corporation_id,
      "alliance_id" => attacker.alliance_id,
      "ship_type_id" => attacker.ship_type_id,
      "weapon_type_id" => attacker.weapon_type_id,
      "damage_done" => attacker.damage_done,
      "final_blow" => attacker.final_blow,
      "security_status" => attacker.security_status,
      # Include enriched fields if present
      "character_name" => attacker.character_name,
      "corporation_name" => attacker.corporation_name,
      "corporation_ticker" => attacker.corporation_ticker,
      "alliance_name" => attacker.alliance_name,
      "alliance_ticker" => attacker.alliance_ticker,
      "ship_name" => attacker.ship_name
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Updates attacker with enriched data from ESI/cache.
  """
  @spec update_with_enriched_data(t(), map()) :: t()
  def update_with_enriched_data(%__MODULE__{} = attacker, enriched_data) when is_map(enriched_data) do
    %{attacker | 
      character_name: enriched_data["character_name"] || enriched_data["attacker_name"] || attacker.character_name,
      corporation_name: enriched_data["corporation_name"] || attacker.corporation_name,
      corporation_ticker: enriched_data["corporation_ticker"] || attacker.corporation_ticker,
      alliance_name: enriched_data["alliance_name"] || attacker.alliance_name,
      alliance_ticker: enriched_data["alliance_ticker"] || attacker.alliance_ticker,
      ship_name: enriched_data["ship_name"] || attacker.ship_name
    }
  end

  @doc """
  Checks if attacker is an NPC (no character_id).
  """
  @spec npc?(t()) :: boolean()
  def npc?(%__MODULE__{character_id: nil}), do: true
  def npc?(%__MODULE__{}), do: false

  @doc """
  Finds the attacker who dealt the final blow.
  """
  @spec find_final_blow([t()]) :: t() | nil
  def find_final_blow(attackers) when is_list(attackers) do
    Enum.find(attackers, & &1.final_blow)
  end

  # Private functions

  defp get_field(map, keys) when is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end
end