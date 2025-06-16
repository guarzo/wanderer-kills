defmodule WandererKills.Domain.Victim do
  @moduledoc """
  Domain struct representing a killmail victim.
  """

  @type t :: %__MODULE__{
          character_id: integer() | nil,
          corporation_id: integer() | nil,
          alliance_id: integer() | nil,
          ship_type_id: integer() | nil,
          damage_taken: integer(),
          position: map() | nil,
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
    :damage_taken,
    :position,
    # Enriched fields
    :character_name,
    :corporation_name,
    :corporation_ticker,
    :alliance_name,
    :alliance_ticker,
    :ship_name
  ]

  @doc """
  Creates a new Victim struct from a map.

  ## Parameters
    - `attrs` - Map with victim attributes

  ## Returns
    - `{:ok, %Victim{}}` - Successfully created victim
    - `{:error, reason}` - Failed to create victim
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    victim = %__MODULE__{
      character_id: get_field(attrs, ["character_id", :character_id]),
      corporation_id: get_field(attrs, ["corporation_id", :corporation_id]),
      alliance_id: get_field(attrs, ["alliance_id", :alliance_id]),
      ship_type_id: get_field(attrs, ["ship_type_id", :ship_type_id]),
      damage_taken: get_field(attrs, ["damage_taken", :damage_taken]) || 0,
      position: get_field(attrs, ["position", :position]),
      # Check for pre-enriched fields
      character_name: get_field(attrs, ["character_name", :character_name, "victim_name"]),
      corporation_name: get_field(attrs, ["corporation_name", :corporation_name]),
      corporation_ticker: get_field(attrs, ["corporation_ticker", :corporation_ticker]),
      alliance_name: get_field(attrs, ["alliance_name", :alliance_name]),
      alliance_ticker: get_field(attrs, ["alliance_ticker", :alliance_ticker]),
      ship_name: get_field(attrs, ["ship_name", :ship_name])
    }

    {:ok, victim}
  end

  @doc """
  Converts a Victim struct to a map for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = victim) do
    %{
      "character_id" => victim.character_id,
      "corporation_id" => victim.corporation_id,
      "alliance_id" => victim.alliance_id,
      "ship_type_id" => victim.ship_type_id,
      "damage_taken" => victim.damage_taken,
      "position" => victim.position,
      # Include enriched fields if present
      "character_name" => victim.character_name,
      "corporation_name" => victim.corporation_name,
      "corporation_ticker" => victim.corporation_ticker,
      "alliance_name" => victim.alliance_name,
      "alliance_ticker" => victim.alliance_ticker,
      "ship_name" => victim.ship_name
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Updates victim with enriched data from ESI/cache.
  """
  @spec update_with_enriched_data(t(), map()) :: t()
  def update_with_enriched_data(%__MODULE__{} = victim, enriched_data)
      when is_map(enriched_data) do
    %{
      victim
      | character_name:
          enriched_data["character_name"] || enriched_data["victim_name"] || victim.character_name,
        corporation_name: enriched_data["corporation_name"] || victim.corporation_name,
        corporation_ticker: enriched_data["corporation_ticker"] || victim.corporation_ticker,
        alliance_name: enriched_data["alliance_name"] || victim.alliance_name,
        alliance_ticker: enriched_data["alliance_ticker"] || victim.alliance_ticker,
        ship_name: enriched_data["ship_name"] || victim.ship_name
    }
  end

  @doc """
  Checks if victim is an NPC (no character_id).
  """
  @spec npc?(t()) :: boolean()
  def npc?(%__MODULE__{character_id: nil}), do: true
  def npc?(%__MODULE__{}), do: false

  # Private functions

  defp get_field(map, keys) when is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end
end
