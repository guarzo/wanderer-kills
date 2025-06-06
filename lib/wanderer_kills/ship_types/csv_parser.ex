defmodule WandererKills.ShipTypes.CSVParser do
  @moduledoc """
  Parser for EVE Online ship type data from the official data dump.
  Uses invTypes.csv and invGroups.csv files from fuzzwork.co.uk.

  This module consolidates CSV parsing functionality for ship type data,
  replacing the previous scattered CSV parsing utilities.
  """

  require Logger
  alias WandererKills.Shared.CSV
  alias WandererKills.ShipTypes.Constants
  alias WandererKills.Infrastructure.Error

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
    data_dir = Constants.data_directory()
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
      # Filter for ship types using ship group IDs from constants
      ship_group_ids = Constants.ship_group_ids()

      ship_types =
        types
        |> Enum.filter(&(&1.group_id in ship_group_ids))
        |> Enum.map(fn type ->
          group = Enum.find(groups, &(&1.group_id == type.group_id))
          Map.put(type, :group_name, group.name)
        end)

      if Enum.empty?(ship_types) do
        {:error,
         Error.ship_types_error(
           :no_ship_types,
           "No ship types found after filtering by ship group IDs",
           %{ship_group_ids: ship_group_ids}
         )}
      else
        {:ok, {ship_types, groups}}
      end
    end
  end
end
