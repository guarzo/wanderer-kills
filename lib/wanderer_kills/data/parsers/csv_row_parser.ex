defmodule WandererKills.Data.Parsers.CsvRowParser do
  @moduledoc """
  Shared CSV row parsing utilities for ship type and group data.

  This module consolidates duplicate CSV parsing logic that was previously
  scattered across multiple modules, providing consistent parsing functions
  for EVE Online ship type and group data from CSV files.

  ## Usage

  ```elixir
  alias WandererKills.Data.Parsers.CsvRowParser

  # Parse a ship type row
  case CsvRowParser.parse_type(csv_row) do
    %{type_id: id, name: name} -> # Success
    nil -> # Failed to parse
  end

  # Parse a group row
  case CsvRowParser.parse_group(csv_row) do
    %{group_id: id, name: name} -> # Success
    nil -> # Failed to parse
  end
  ```
  """

  alias WandererKills.Data.Parsers.CsvUtil

  @type ship_type :: %{
          type_id: integer(),
          name: String.t(),
          group_id: integer(),
          group_name: String.t() | nil,
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
  Parses a CSV row into a ship type map.

  Extracts ship type information from a CSV row map, converting string values
  to appropriate types and handling missing or invalid data gracefully.

  ## Parameters
  - `row` - A map representing a CSV row with string keys and values

  ## Returns
  - A ship type map with parsed values, or `nil` if parsing fails

  ## Examples

  ```elixir
  row = %{"typeID" => "123", "typeName" => "Rifter", "groupID" => "25"}
  %{type_id: 123, name: "Rifter", group_id: 25} = parse_type(row)
  ```
  """
  @spec parse_type(map()) :: ship_type() | nil
  def parse_type(row) when is_map(row) do
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

  def parse_type(_), do: nil

  @doc """
  Parses a CSV row into a ship group map.

  Extracts ship group information from a CSV row map, converting string values
  to appropriate types and handling missing or invalid data gracefully.

  ## Parameters
  - `row` - A map representing a CSV row with string keys and values

  ## Returns
  - A ship group map with parsed values, or `nil` if parsing fails

  ## Examples

  ```elixir
  row = %{"groupID" => "25", "groupName" => "Frigate", "categoryID" => "6"}
  %{group_id: 25, name: "Frigate", category_id: 6} = parse_group(row)
  ```
  """
  @spec parse_group(map()) :: ship_group() | nil
  def parse_group(row) when is_map(row) do
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

  def parse_group(_), do: nil
end
