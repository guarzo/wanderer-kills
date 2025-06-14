defmodule WandererKills.Domain.ZkbMetadata do
  @moduledoc """
  Domain struct representing zKillboard metadata for a killmail.
  """

  @type t :: %__MODULE__{
          location_id: integer() | nil,
          hash: String.t(),
          fitted_value: float() | nil,
          dropped_value: float() | nil,
          destroyed_value: float() | nil,
          total_value: float() | nil,
          points: integer() | nil,
          npc: boolean(),
          solo: boolean(),
          awox: boolean(),
          labels: [String.t()] | nil
        }

  defstruct [
    :location_id,
    :hash,
    :fitted_value,
    :dropped_value,
    :destroyed_value,
    :total_value,
    :points,
    :npc,
    :solo,
    :awox,
    :labels
  ]

  @doc """
  Creates a new ZkbMetadata struct from a map.

  ## Parameters
    - `attrs` - Map with zkb metadata attributes

  ## Returns
    - `{:ok, %ZkbMetadata{}}` - Successfully created metadata
    - `{:error, reason}` - Failed to create metadata
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    zkb = %__MODULE__{
      location_id: get_field(attrs, ["locationID", "location_id", :location_id]),
      hash: get_field(attrs, ["hash", :hash]),
      fitted_value: get_field(attrs, ["fittedValue", "fitted_value", :fitted_value]),
      dropped_value: get_field(attrs, ["droppedValue", "dropped_value", :dropped_value]),
      destroyed_value: get_field(attrs, ["destroyedValue", "destroyed_value", :destroyed_value]),
      total_value: get_field(attrs, ["totalValue", "total_value", :total_value]),
      points: get_field(attrs, ["points", :points]),
      npc: get_field(attrs, ["npc", :npc]) || false,
      solo: get_field(attrs, ["solo", :solo]) || false,
      awox: get_field(attrs, ["awox", :awox]) || false,
      labels: get_field(attrs, ["labels", :labels])
    }

    if zkb.hash do
      {:ok, zkb}
    else
      {:error, :missing_zkb_hash}
    end
  end

  @doc """
  Converts a ZkbMetadata struct to a map for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = zkb) do
    %{
      "locationID" => zkb.location_id,
      "hash" => zkb.hash,
      "fittedValue" => zkb.fitted_value,
      "droppedValue" => zkb.dropped_value,
      "destroyedValue" => zkb.destroyed_value,
      "totalValue" => zkb.total_value,
      "points" => zkb.points,
      "npc" => zkb.npc,
      "solo" => zkb.solo,
      "awox" => zkb.awox,
      "labels" => zkb.labels
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Checks if this killmail involves NPCs.
  """
  @spec npc_kill?(t()) :: boolean()
  def npc_kill?(%__MODULE__{npc: npc}), do: npc

  @doc """
  Checks if this was a solo kill.
  """
  @spec solo_kill?(t()) :: boolean()
  def solo_kill?(%__MODULE__{solo: solo}), do: solo

  @doc """
  Checks if this was an AWOX (friendly fire) kill.
  """
  @spec awox_kill?(t()) :: boolean()
  def awox_kill?(%__MODULE__{awox: awox}), do: awox

  @doc """
  Gets the killmail value in ISK.
  """
  @spec value(t()) :: float()
  def value(%__MODULE__{total_value: total}) when is_number(total), do: total
  def value(%__MODULE__{}), do: 0.0

  # Private functions

  defp get_field(map, keys) when is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end
end