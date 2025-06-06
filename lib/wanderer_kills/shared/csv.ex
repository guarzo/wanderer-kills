defmodule WandererKills.Shared.CSV do
  @moduledoc """
  Unified CSV parsing utilities for WandererKills.

  This module consolidates all CSV parsing functionality that was previously
  scattered across multiple modules, providing consistent parsing, validation,
  and error handling for all CSV data sources in the application.

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
  ship_type = CSV.parse_ship_type(csv_row_map)
  ship_group = CSV.parse_ship_group(csv_row_map)
  ```
  """

  require Logger
  alias NimbleCSV.RFC4180, as: CSV
  alias WandererKills.Infrastructure.Error

  @type parse_result :: {:ok, term()} | {:error, atom()}
  @type parser_function :: (map() -> term() | nil)
  @type validator_function :: (term() -> boolean())

  # =============================================================================
  # Public API - File Reading
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
  @spec read_file(String.t(), parser_function(), keyword()) :: {:ok, [term()]} | {:error, atom()}
  def read_file(file_path, parser, opts \\ []) do
    skip_invalid = Keyword.get(opts, :skip_invalid, true)
    max_errors = Keyword.get(opts, :max_errors, 10)

    case File.read(file_path) do
      {:ok, content} ->
        parse_csv_content(content, parser, skip_invalid, max_errors)

      {:error, reason} ->
        Logger.error("Failed to read CSV file #{file_path}: #{inspect(reason)}")
        {:error, reason}
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
          {:ok, [term()]} | {:error, atom()}
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

  # =============================================================================
  # Public API - Row Parsing
  # =============================================================================

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

  # =============================================================================
  # Public API - Number Parsing
  # =============================================================================

  @doc """
  Parses a string value to integer with error handling.
  """
  @spec parse_integer(String.t()) :: {:ok, integer()} | {:error, Error.t()}
  def parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} ->
        {:ok, int}

      _ ->
        {:error,
         Error.parsing_error(:invalid_integer, "Failed to parse string as integer", %{
           value: value
         })}
    end
  end

  def parse_integer(value) do
    {:error,
     Error.parsing_error(:invalid_integer, "Cannot parse non-string value as integer", %{
       value: inspect(value)
     })}
  end

  @doc """
  Parses a string value to float with error handling.
  """
  @spec parse_float(String.t()) :: {:ok, float()} | {:error, Error.t()}
  def parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} ->
        {:ok, float}

      :error ->
        {:error,
         Error.parsing_error(:invalid_float, "Failed to parse string as float", %{value: value})}
    end
  end

  def parse_float(value) do
    {:error,
     Error.parsing_error(:invalid_float, "Cannot parse non-string value as float", %{
       value: inspect(value)
     })}
  end

  @doc """
  Parses a number with a default value on error.
  """
  @spec parse_number_with_default(String.t(), :integer | :float, number()) :: number()
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

  # =============================================================================
  # EVE Online Specific Parsers
  # =============================================================================

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

  def parse_ship_type(_), do: nil

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

  def parse_ship_group(_), do: nil

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
          {:error, Error.parsing_error(:empty_file, "CSV file is empty or has no headers")}
      end
    rescue
      e ->
        Logger.error("Failed to parse CSV content: #{inspect(e)}")

        {:error,
         Error.parsing_error(:parse_error, "Exception during CSV parsing", %{
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
       Error.parsing_error(:too_many_errors, "CSV parsing failed with too many errors", %{
         error_count: length(errors),
         max_errors: max_errors
       })}
    else
      if length(errors) > 0 do
        Logger.warning("CSV parsing completed with #{length(errors)} errors")
      end

      {:ok, Enum.reverse(records)}
    end
  end
end
