defmodule WandererKills.Core.CSV do
  @moduledoc """
  Unified CSV parsing utilities for WandererKills.

  This module consolidates all CSV parsing functionality from across the codebase,
  providing consistent parsing, validation, and error handling for all CSV data
  sources in the application.

  ## Features

  - Standardized CSV file reading with error handling
  - Generic row parsing with header mapping
  - Type-safe number parsing with defaults
  - Schema validation for structured data
  - EVE Online specific parsing for ship types and groups

  ## Usage

  ```elixir
  # Basic CSV reading
  {:ok, records} = CSV.read_file(path, &parse_my_record/1)

  # With validation
  {:ok, records} = CSV.read_file_with_validation(path, &parse_my_record/1, &validate_record/1)

  # Parse specific EVE data
  ship_type = CSV.parse_type_row(csv_row_map)
  ship_group = CSV.parse_group_row(csv_row_map)
  ```
  """

  require Logger
  alias NimbleCSV.RFC4180, as: CSVParser
  alias WandererKills.Core.Error

  @type parse_result :: {:ok, term()} | {:error, Error.t()}
  @type parser_function :: (map() -> term() | nil)
  @type validator_function :: (term() -> boolean())

  @type ship_type :: %{
          type_id: integer(),
          name: String.t(),
          group_id: integer(),
          mass: float(),
          volume: float(),
          capacity: float(),
          portion_size: integer(),
          race_id: integer(),
          base_price: float(),
          published: boolean(),
          market_group_id: integer(),
          icon_id: integer(),
          sound_id: integer(),
          graphic_id: integer()
        }

  @type ship_group :: %{
          group_id: integer(),
          category_id: integer(),
          name: String.t(),
          icon_id: integer(),
          use_base_price: boolean(),
          anchored: boolean(),
          anchorable: boolean(),
          fittable_non_singleton: boolean(),
          published: boolean()
        }

  # ============================================================================
  # File Reading API
  # ============================================================================

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
  @spec read_file(String.t(), parser_function(), keyword()) ::
          {:ok, [term()]} | {:error, Error.t()}
  def read_file(file_path, parser, opts \\ []) do
    skip_invalid = Keyword.get(opts, :skip_invalid, true)
    max_errors = Keyword.get(opts, :max_errors, 10)

    case File.read(file_path) do
      {:ok, content} ->
        parse_csv_content(content, parser, skip_invalid, max_errors)

      {:error, reason} ->
        Logger.error("Failed to read CSV file #{file_path}: #{inspect(reason)}")

        {:error,
         Error.csv_error(:file_read_error, "Failed to read CSV file: #{file_path}", %{
           file_path: file_path,
           reason: reason
         })}
    end
  end

  @doc """
  Reads a CSV file with validation of parsed records.

  ## Parameters
  - `file_path` - Path to the CSV file
  - `parser` - Function that converts a row map to a record
  - `validator` - Function that validates a parsed record (returns boolean)
  - `opts` - Same as read_file/3

  ## Returns
  - `{:ok, records}` - List of successfully parsed and validated records
  - `{:error, reason}` - Parse/validation error or file error
  """
  @spec read_file_with_validation(String.t(), parser_function(), validator_function(), keyword()) ::
          {:ok, [term()]} | {:error, Error.t()}
  def read_file_with_validation(file_path, parser, validator, opts \\ []) do
    case read_file(file_path, parser, opts) do
      {:ok, records} ->
        valid_records = Enum.filter(records, validator)
        invalid_count = length(records) - length(valid_records)

        if invalid_count > 0 do
          Logger.warning("Filtered out #{invalid_count} invalid records from #{file_path}")
        end

        {:ok, valid_records}

      error ->
        error
    end
  end

  # ============================================================================
  # Row Parsing API
  # ============================================================================

  @doc """
  Parses a CSV data row into a map using the provided headers.

  ## Parameters
  - `row` - List of values from a CSV row
  - `headers` - List of header names

  ## Returns
  Map with headers as keys and row values as values
  """
  @spec parse_row(list(String.t()), list(String.t())) :: map()
  def parse_row(row, headers) do
    headers
    |> Enum.zip(row)
    |> Map.new()
  end

  # ============================================================================
  # Number Parsing API
  # ============================================================================

  @doc """
  Parses a string value to integer with error handling.
  """
  @spec parse_integer(String.t() | nil) :: {:ok, integer()} | {:error, Error.t()}
  def parse_integer(value) when is_binary(value) and value != "" do
    case Integer.parse(value) do
      {int, ""} ->
        {:ok, int}

      _ ->
        {:error,
         Error.csv_error(:invalid_integer, "Failed to parse string as integer", %{
           value: value
         })}
    end
  end

  def parse_integer(value) when value in [nil, ""] do
    {:error,
     Error.csv_error(:missing_value, "Cannot parse empty/nil value as integer", %{
       value: inspect(value)
     })}
  end

  def parse_integer(value) do
    {:error,
     Error.csv_error(:invalid_type, "Cannot parse non-string value as integer", %{
       value: inspect(value)
     })}
  end

  @doc """
  Parses a string value to float with error handling.
  """
  @spec parse_float(String.t() | nil) :: {:ok, float()} | {:error, Error.t()}
  def parse_float(value) when is_binary(value) and value != "" do
    case Float.parse(value) do
      {float, _} ->
        {:ok, float}

      :error ->
        {:error,
         Error.csv_error(:invalid_float, "Failed to parse string as float", %{value: value})}
    end
  end

  def parse_float(value) when value in [nil, ""] do
    {:error,
     Error.csv_error(:missing_value, "Cannot parse empty/nil value as float", %{
       value: inspect(value)
     })}
  end

  def parse_float(value) do
    {:error,
     Error.csv_error(:invalid_type, "Cannot parse non-string value as float", %{
       value: inspect(value)
     })}
  end

  @doc """
  Parses a number with a default value on error.
  """
  @spec parse_number_with_default(String.t() | nil, :integer | :float, number()) :: number()
  def parse_number_with_default(value, type, default) do
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

  @doc """
  Parses a boolean value from common CSV representations.
  """
  @spec parse_boolean(String.t() | nil, boolean()) :: boolean()
  def parse_boolean(value, default \\ false)

  def parse_boolean(value, _default) when value in ["1", "true", "TRUE", "True", "yes", "YES"],
    do: true

  def parse_boolean(value, _default) when value in ["0", "false", "FALSE", "False", "no", "NO"],
    do: false

  def parse_boolean(_value, default), do: default

  # ============================================================================
  # EVE Online Specific Parsers
  # ============================================================================

  @doc """
  Parses a CSV row map into a ship type record.

  Expected columns: typeID, typeName, groupID, mass, volume, capacity,
  portionSize, raceID, basePrice, published, marketGroupID, iconID, soundID, graphicID
  """
  @spec parse_type_row(map()) :: ship_type() | nil
  def parse_type_row(row) when is_map(row) do
    try do
      %{
        type_id: parse_number_with_default(row["typeID"], :integer, 0),
        name: Map.get(row, "typeName", ""),
        group_id: parse_number_with_default(row["groupID"], :integer, 0),
        mass: parse_number_with_default(row["mass"], :float, 0.0),
        volume: parse_number_with_default(row["volume"], :float, 0.0),
        capacity: parse_number_with_default(row["capacity"], :float, 0.0),
        portion_size: parse_number_with_default(row["portionSize"], :integer, 1),
        race_id: parse_number_with_default(row["raceID"], :integer, 0),
        base_price: parse_number_with_default(row["basePrice"], :float, 0.0),
        published: parse_boolean(row["published"], false),
        market_group_id: parse_number_with_default(row["marketGroupID"], :integer, 0),
        icon_id: parse_number_with_default(row["iconID"], :integer, 0),
        sound_id: parse_number_with_default(row["soundID"], :integer, 0),
        graphic_id: parse_number_with_default(row["graphicID"], :integer, 0)
      }
    rescue
      error ->
        Logger.warning("Failed to parse ship type row: #{inspect(error)}, row: #{inspect(row)}")
        nil
    end
  end

  def parse_type_row(_), do: nil

  @doc """
  Parses a CSV row map into a ship group record.

  Expected columns: groupID, categoryID, groupName, iconID, useBasePrice,
  anchored, anchorable, fittableNonSingleton, published
  """
  @spec parse_group_row(map()) :: ship_group() | nil
  def parse_group_row(row) when is_map(row) do
    try do
      %{
        group_id: parse_number_with_default(row["groupID"], :integer, 0),
        category_id: parse_number_with_default(row["categoryID"], :integer, 0),
        name: Map.get(row, "groupName", ""),
        icon_id: parse_number_with_default(row["iconID"], :integer, 0),
        use_base_price: parse_boolean(row["useBasePrice"], false),
        anchored: parse_boolean(row["anchored"], false),
        anchorable: parse_boolean(row["anchorable"], false),
        fittable_non_singleton: parse_boolean(row["fittableNonSingleton"], false),
        published: parse_boolean(row["published"], false)
      }
    rescue
      error ->
        Logger.warning("Failed to parse ship group row: #{inspect(error)}, row: #{inspect(row)}")
        nil
    end
  end

  def parse_group_row(_), do: nil

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec parse_csv_content(String.t(), parser_function(), boolean(), pos_integer()) ::
          {:ok, [term()]} | {:error, Error.t()}
  defp parse_csv_content(content, parser, skip_invalid, max_errors) do
    try do
      rows =
        content
        |> CSVParser.parse_string(skip_headers: false)
        |> Enum.to_list()

      case rows do
        [] ->
          {:ok, []}

        [headers | data_rows] ->
          process_rows(data_rows, headers, parser, skip_invalid, max_errors)
      end
    rescue
      error ->
        Logger.error("CSV parsing failed: #{inspect(error)}")

        {:error,
         Error.csv_error(:parse_error, "Failed to parse CSV content", %{
           error: inspect(error)
         })}
    end
  end

  @spec process_rows([list()], list(), parser_function(), boolean(), pos_integer()) ::
          {:ok, [term()]} | {:error, Error.t()}
  defp process_rows(data_rows, headers, parser, skip_invalid, max_errors) do
    {records, errors} =
      data_rows
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {row, line_num}, {acc_records, acc_errors} ->
        if length(acc_errors) >= max_errors do
          {acc_records, acc_errors}
        else
          try do
            row_map = parse_row(row, headers)
            result = parser.(row_map)

            cond do
              result == nil and skip_invalid ->
                {acc_records, acc_errors}

              result == nil ->
                error = "Parser returned nil for row #{line_num}"
                {acc_records, [error | acc_errors]}

              true ->
                {[result | acc_records], acc_errors}
            end
          rescue
            error ->
              error_msg = "Parse error on line #{line_num}: #{inspect(error)}"
              {acc_records, [error_msg | acc_errors]}
          end
        end
      end)

    if length(errors) >= max_errors do
      Logger.error("Too many CSV parse errors (#{length(errors)} >= #{max_errors})")

      {:error,
       Error.csv_error(:too_many_errors, "Exceeded maximum parse errors", %{
         error_count: length(errors),
         max_errors: max_errors,
         errors: Enum.reverse(errors)
       })}
    else
      if length(errors) > 0 do
        Logger.warning("CSV parsing completed with #{length(errors)} errors")
      end

      {:ok, Enum.reverse(records)}
    end
  end
end
