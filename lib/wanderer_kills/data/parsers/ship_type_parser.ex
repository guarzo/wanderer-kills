defmodule WandererKills.Data.Parsers.ShipTypeParser do
  @moduledoc """
  Parser for EVE Online ship type data from the official data dump.
  Uses invTypes.csv and invGroups.csv files from fuzzwork.co.uk.
  """

  require Logger
  alias WandererKills.Data.Parsers.CsvUtil

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

    with {:ok, types} <- CsvUtil.read_rows(types_path, &parse_type_row/1),
         {:ok, groups} <- CsvUtil.read_rows(groups_path, &parse_group_row/1) do
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

  # CSV row parsers
  defp parse_type_row(row) when is_map(row) do
    try do
      with type_id when is_binary(type_id) <- Map.get(row, "typeID"),
           group_id when is_binary(group_id) <- Map.get(row, "groupID"),
           name when is_binary(name) <- Map.get(row, "typeName") do
        %{
          type_id: String.to_integer(type_id),
          group_id: String.to_integer(group_id),
          name: name,
          group_name: nil,
          mass: CsvUtil.parse_float_with_default(Map.get(row, "mass", "0")),
          capacity: CsvUtil.parse_float_with_default(Map.get(row, "capacity", "0")),
          volume: CsvUtil.parse_float_with_default(Map.get(row, "volume", "0"))
        }
      else
        _ -> nil
      end
    rescue
      ArgumentError -> nil
    end
  end

  defp parse_type_row(_), do: nil

  defp parse_group_row(row) when is_map(row) do
    try do
      with group_id when is_binary(group_id) <- Map.get(row, "groupID"),
           name when is_binary(name) <- Map.get(row, "groupName"),
           category_id when is_binary(category_id) <- Map.get(row, "categoryID") do
        %{
          group_id: String.to_integer(group_id),
          name: name,
          category_id: String.to_integer(category_id)
        }
      else
        _ -> nil
      end
    rescue
      ArgumentError -> nil
    end
  end

  defp parse_group_row(_), do: nil
end
