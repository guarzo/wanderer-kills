defmodule WandererKills.Parser.ShipTypeParser do
  @moduledoc """
  Parser for EVE Online ship type data from the official data dump.
  Uses invTypes.csv and invGroups.csv files from fuzzwork.co.uk.

  Note: This module now uses the unified WandererKills.Shared.CSV module
  for all CSV parsing operations.
  """

  require Logger
  alias WandererKills.Shared.CSV

  @type ship_type :: %{
          type_id: integer(),
          name: String.t(),
          group_id: integer(),
          group_name: String.t(),
          mass: float() | nil,
          volume: float() | nil,
          capacity: float() | nil
        }

  @type ship_group :: %{
          group_id: integer(),
          name: String.t(),
          category_id: integer()
        }

  @doc """
  Loads ship type data from CSV files.
  Returns {:ok, {types, groups}} or {:error, reason}
  """
  def load_ship_data do
    priv_dir = :code.priv_dir(:wanderer_kills)
    data_dir = Path.join([priv_dir, "data"])
    File.mkdir_p!(data_dir)

    load_ship_data(data_dir)
  end

  @doc """
  Loads ship type data from the CSV files.
  """
  def load_ship_data(data_dir) do
    types_path = Path.join([data_dir, "invTypes.csv"])
    groups_path = Path.join([data_dir, "invGroups.csv"])

    with {:ok, types} <- CSV.read_file(types_path, &CSV.parse_ship_type/1),
         {:ok, groups} <- CSV.read_file(groups_path, &CSV.parse_ship_group/1) do
      # Filter for ship types (group category ID 6)
      ship_types =
        types
        |> Enum.filter(&(&1.group_id in [6, 7, 9, 11, 16, 17, 23]))
        |> Enum.map(fn type ->
          group = Enum.find(groups, &(&1.group_id == type.group_id))
          Map.put(type, :group_name, group.name)
        end)

      if Enum.empty?(ship_types) do
        {:error, :no_ship_types}
      else
        {:ok, {ship_types, groups}}
      end
    end
  end
end
