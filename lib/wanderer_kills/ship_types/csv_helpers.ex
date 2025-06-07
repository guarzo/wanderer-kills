defmodule WandererKills.ShipTypes.CSVHelpers do
  @moduledoc """
  Consolidated CSV parsing for ship type data.
  Merges functionality from shared/csv.ex and ship_type_parser.ex

  This module provides ship-type specific CSV parsing utilities, moving
  the EVE Online specific parsing logic out of the generic CSV module
  and consolidating all ship type parsing in one place.
  """

  require Logger
  alias NimbleCSV.RFC4180, as: CSV
  alias WandererKills.ShipTypes.Constants
  alias WandererKills.Core.Error

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

  @type parse_result :: {:ok, [term()]} | {:error, Error.t()}
  @type parser_function :: (map() -> term() | nil)

  # =============================================================================
  # Public API - High-level Loading Functions
  # =============================================================================

  @doc """
  Loads ship type data from CSV files in the default data directory.
  Returns {:ok, {types, groups}} or {:error, reason}
  """
  @spec load_ship_data() :: {:ok, {[ship_type()], [ship_group()]}} | {:error, Error.t()}
  def load_ship_data do
    data_dir = Constants.data_directory()
    File.mkdir_p!(data_dir)
    load_ship_data(data_dir)
  end

  @doc """
  Loads ship type data from the specified CSV files directory.
  """
  @spec load_ship_data(String.t()) :: {:ok, {[ship_type()], [ship_group()]}} | {:error, Error.t()}
  def load_ship_data(data_dir) do
    types_path = Path.join([data_dir, "invTypes.csv"])
    groups_path = Path.join([data_dir, "invGroups.csv"])

    with {:ok, types} <- read_file(types_path, &parse_ship_type/1),
         {:ok, groups} <- read_file(groups_path, &parse_ship_group/1) do
      filter_ship_types(types, groups)
    end
  end

  @doc """
  Filters raw ship types to only include actual ships based on group IDs.
  """
  @spec filter_ship_types([ship_type()], [ship_group()]) ::
          {:ok, {[ship_type()], [ship_group()]}} | {:error, Error.t()}
  def filter_ship_types(types, groups) do
    ship_group_ids = Constants.ship_group_ids()

    ship_types =
      types
      |> Enum.filter(&(&1.group_id in ship_group_ids))
      |> Enum.map(fn type ->
        group = Enum.find(groups, &(&1.group_id == type.group_id))
        group_name = if group, do: group.name, else: nil
        Map.put(type, :group_name, group_name)
      end)

    if Enum.empty?(ship_types) do
      {:error,
       Error.ship_types_error(
         :no_ship_types,
         "No ship types found after filtering by ship group IDs",
         false,
         %{ship_group_ids: ship_group_ids}
       )}
    else
      {:ok, {ship_types, groups}}
    end
  end

  # =============================================================================
  # Public API - CSV File Reading
  # =============================================================================

  @doc """
  Reads a CSV file and converts each row to a record using the provided parser function.

  ## Parameters
  - `file_path` - Path to the CSV file
  - `parser` - Function that converts a row map to a record (returns nil to skip)
  - `opts` - Optional parameters:
    - `:skip_invalid` - Skip rows that return nil from parser (default: true)
    - `:max_errors` - Maximum parse errors before giving up (default: 10)

  ## Returns
  - `{:ok, records}` - List of successfully parsed records
  - `{:error, reason}` - Parse error or file error
  """
  @spec read_file(String.t(), parser_function(), keyword()) :: parse_result()
  def read_file(file_path, parser, opts \\ []) do
    skip_invalid = Keyword.get(opts, :skip_invalid, true)
    max_errors = Keyword.get(opts, :max_errors, 10)

    case File.read(file_path) do
      {:ok, content} ->
        parse_csv_content(content, parser, skip_invalid, max_errors)

      {:error, reason} ->
        Logger.error("Failed to read CSV file #{file_path}: #{inspect(reason)}")

        {:error,
         Error.ship_types_error(:file_read_error, "Failed to read CSV file", false, %{
           file_path: file_path,
           reason: reason
         })}
    end
  end

  # =============================================================================
  # Public API - Ship Type Specific Parsers
  # =============================================================================

  @doc """
  Parses a CSV row into a ship type map for EVE Online data.

  ## Parameters
  - `row` - A map representing a CSV row with string keys and values

  ## Returns
  - A ship type map with parsed values, or `nil` if parsing fails
  """
  @spec parse_ship_type(map()) :: ship_type() | nil
  def parse_ship_type(row) when is_map(row) do
    try do
      with type_id when is_binary(type_id) <- Map.get(row, "typeID"),
           group_id when is_binary(group_id) <- Map.get(row, "groupID"),
           name when is_binary(name) <- Map.get(row, "typeName") do
        %{
          type_id: String.to_integer(type_id),
          group_id: String.to_integer(group_id),
          name: name,
          group_name: nil,
          mass: parse_number_with_default(Map.get(row, "mass", "0"), :float, 0.0),
          capacity: parse_number_with_default(Map.get(row, "capacity", "0"), :float, 0.0),
          volume: parse_number_with_default(Map.get(row, "volume", "0"), :float, 0.0)
        }
      else
        _ -> nil
      end
    rescue
      ArgumentError -> nil
    end
  end

  @doc """
  Parses a CSV row into a ship group map for EVE Online data.

  ## Parameters
  - `row` - A map representing a CSV row with string keys and values

  ## Returns
  - A ship group map with parsed values, or `nil` if parsing fails
  """
  @spec parse_ship_group(map()) :: ship_group() | nil
  def parse_ship_group(row) when is_map(row) do
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

  # =============================================================================
  # Public API - Utility Functions
  # =============================================================================

  @doc """
  Parses a CSV data row into a map using the provided headers.
  """
  @spec parse_row(list(String.t()), list(String.t())) :: map()
  def parse_row(row, headers) do
    headers
    |> Enum.zip(row)
    |> Map.new()
  end

  @doc """
  Parses a number with a default value on error.
  """
  @spec parse_number_with_default(String.t(), :integer | :float, number()) :: number()
  def parse_number_with_default(value, type, default) when is_binary(value) do
    result =
      case type do
        :integer -> parse_integer(value)
        :float -> parse_float(value)
      end

    case result do
      {:ok, number} -> number
      {:error, _} -> default
    end
  end

  def parse_number_with_default(_, _, default), do: default

  # =============================================================================
  # Private Helper Functions
  # =============================================================================

  defp parse_csv_content(content, parser, skip_invalid, max_errors) do
    try do
      # Parse the CSV content using NimbleCSV with headers included
      {headers, rows} =
        content
        |> CSV.parse_string(skip_headers: false)
        |> Enum.split(1)

      case headers do
        [header_row] when is_list(header_row) ->
          headers = Enum.map(header_row, &String.trim/1)
          parse_rows(rows, headers, parser, skip_invalid, max_errors)

        _ ->
          {:error, Error.ship_types_error(:empty_file, "CSV file is empty or has no headers")}
      end
    rescue
      e ->
        Logger.error("Failed to parse CSV content: #{inspect(e)}")

        {:error,
         Error.ship_types_error(:parse_error, "Exception during CSV parsing", false, %{
           exception: inspect(e)
         })}
    end
  end

  defp parse_rows(rows, headers, parser, skip_invalid, max_errors) do
    {records, errors} =
      rows
      |> Stream.with_index()
      |> Stream.map(fn {row, index} ->
        try do
          row_map = parse_row(row, headers)

          case parser.(row_map) do
            nil when skip_invalid -> :skip
            nil -> {:error, {:row, index + 2, :parser_returned_nil}}
            result -> {:ok, result}
          end
        rescue
          e -> {:error, {:row, index + 2, e}}
        end
      end)
      |> Enum.reduce({[], []}, fn
        :skip, {records, errors} -> {records, errors}
        {:ok, record}, {records, errors} -> {[record | records], errors}
        {:error, error}, {records, errors} -> {records, [error | errors]}
      end)

    # Check if we have too many errors
    if length(errors) > max_errors do
      Logger.error("Too many CSV parse errors (#{length(errors)} > #{max_errors})")

      {:error,
       Error.ship_types_error(
         :too_many_errors,
         "CSV parsing failed with too many errors",
         false,
         %{
           error_count: length(errors),
           max_errors: max_errors
         }
       )}
    else
      if length(errors) > 0 do
        Logger.warning("CSV parsing completed with #{length(errors)} errors")
      end

      {:ok, Enum.reverse(records)}
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> {:ok, float}
      :error -> {:error, :invalid_float}
    end
  end
end
