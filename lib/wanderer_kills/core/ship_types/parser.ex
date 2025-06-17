defmodule WandererKills.Core.ShipTypes.Parser do
  @moduledoc """
  CSV parsing functionality for ship types and groups.

  This module handles the parsing of EVE Online CSV data files,
  converting raw CSV data into structured Elixir data types.
  """

  require Logger
  alias NimbleCSV.RFC4180, as: CSVParser
  alias WandererKills.Core.Support.Error

  @type parser_function :: (map() -> term() | nil)
  @type parse_result :: {:ok, term()} | {:error, Error.t()}

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
  # File Reading
  # ============================================================================

  @doc """
  Reads a CSV file and converts each row to a record using the provided parser function.

  ## Parameters
  - `file_path` - Path to the CSV file
  - `parser` - Function that converts a row map to a record (returns nil to skip)
  - `opts` - Optional parameters:
    - `:skip_invalid` - Skip rows that return nil from parser (default: true)
    - `:max_errors` - Maximum parse errors before giving up (default: 10)
  """
  @spec read_file(String.t(), parser_function(), keyword()) ::
          {:ok, {[term()], map()}} | {:error, Error.t()}
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
  Parses CSV content and returns parsed records.
  """
  @spec parse_csv_content(String.t(), parser_function(), boolean(), integer()) ::
          {:ok, {[term()], map()}} | {:error, Error.t()}
  def parse_csv_content(content, parser, skip_invalid, max_errors) do
    parsed_data = CSVParser.parse_string(content, skip_headers: false)

    case parsed_data do
      [] ->
        {:error, Error.csv_error(:empty_file, "CSV file is empty")}

      [headers | data_rows] ->
        headers = Enum.map(headers, &String.trim/1)
        process_rows(data_rows, headers, parser, skip_invalid, max_errors)
    end
  rescue
    error ->
      Logger.error("Failed to parse CSV content: #{inspect(error)}")

      {:error,
       Error.csv_error(:parse_failure, "CSV parsing failed", %{
         error: inspect(error)
       })}
  end

  # ============================================================================
  # Row Parsing
  # ============================================================================

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
  Parses a ship type row from CSV data.
  """
  @spec parse_type_row(map()) :: {:ok, ship_type()} | {:error, String.t()}
  def parse_type_row(row) when is_map(row) do
    # Build the ship type data structure
    # All parsing functions return safe defaults, so this should not fail
    ship_type = %{
      type_id: parse_number_with_default(row["typeID"], :integer, 0),
      name: Map.get(row, "typeName", ""),
      group_id: parse_number_with_default(row["groupID"], :integer, 0),
      mass: parse_number_with_default(row["mass"], :float, 0.0),
      volume: parse_number_with_default(row["volume"], :float, 0.0),
      capacity: parse_number_with_default(row["capacity"], :float, 0.0),
      portion_size: parse_number_with_default(row["portionSize"], :integer, 1),
      race_id: parse_number_with_default(row["raceID"], :integer, 0),
      base_price: parse_number_with_default(row["basePrice"], :float, 0.0),
      published: parse_boolean(row["published"]),
      market_group_id: parse_number_with_default(row["marketGroupID"], :integer, 0),
      icon_id: parse_number_with_default(row["iconID"], :integer, 0),
      sound_id: parse_number_with_default(row["soundID"], :integer, 0),
      graphic_id: parse_number_with_default(row["graphicID"], :integer, 0)
    }

    # Validate required fields
    cond do
      ship_type.type_id == 0 ->
        {:error, "Invalid ship type: missing or invalid typeID"}

      ship_type.name == "" ->
        {:error, "Invalid ship type: missing typeName"}

      true ->
        {:ok, ship_type}
    end
  end

  def parse_type_row(_row), do: {:error, "Invalid row format: expected map"}

  @doc """
  Parses a ship group row from CSV data.

  Returns the parsed ship group or nil if parsing fails.
  This function is designed to work with Parser.read_file which
  handles nil returns appropriately.
  """
  @spec parse_group_row(map()) :: ship_group() | nil
  def parse_group_row(row) when is_map(row) do
    %{
      group_id: parse_number_with_default(row["groupID"], :integer, 0),
      category_id: parse_number_with_default(row["categoryID"], :integer, 0),
      name: Map.get(row, "groupName", ""),
      icon_id: parse_number_with_default(row["iconID"], :integer, 0),
      use_base_price: parse_boolean(row["useBasePrice"]),
      anchored: parse_boolean(row["anchored"]),
      anchorable: parse_boolean(row["anchorable"]),
      fittable_non_singleton: parse_boolean(row["fittableNonSingleton"]),
      published: parse_boolean(row["published"])
    }
  rescue
    error ->
      Logger.warning("Failed to parse ship group row: #{inspect(error)}, row: #{inspect(row)}")
      nil
  end

  def parse_group_row(_row), do: nil

  # ============================================================================
  # Number Parsing Utilities
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
      {float, ""} ->
        {:ok, float}

      _ ->
        {:error,
         Error.csv_error(:invalid_float, "Failed to parse string as float", %{
           value: value
         })}
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
  Parses a number with a default value on failure.

  This is a convenience function that attempts to parse a value
  and returns a default if parsing fails.
  """
  @spec parse_number_with_default(String.t() | nil, :integer | :float, number()) :: number()
  def parse_number_with_default(value, type, default) do
    case type do
      :integer ->
        case parse_integer(value) do
          {:ok, int} -> int
          {:error, _} -> default
        end

      :float ->
        case parse_float(value) do
          {:ok, float} -> float
          {:error, _} -> default
        end
    end
  end

  @doc """
  Parses a boolean value from various string representations.
  """
  @spec parse_boolean(String.t() | nil) :: boolean()
  def parse_boolean(value) when value in ["1", "true", "True", "TRUE"], do: true
  def parse_boolean(_), do: false

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp process_rows(data_rows, headers, parser, skip_invalid, max_errors) do
    {records, stats} =
      data_rows
      |> Enum.reduce_while({[], %{parsed: 0, skipped: 0, errors: 0}}, fn row, {acc, stats} ->
        process_single_row(row, {acc, stats}, headers, parser, skip_invalid, max_errors)
      end)

    if stats.errors >= max_errors do
      Logger.error("CSV parsing aborted after #{max_errors} errors")

      {:error,
       Error.csv_error(:too_many_errors, "Too many parsing errors", %{
         max_errors: max_errors,
         stats: stats
       })}
    else
      {:ok, {Enum.reverse(records), stats}}
    end
  end

  defp process_single_row(row, {acc, stats}, headers, parser, skip_invalid, max_errors) do
    if stats.errors >= max_errors do
      {:halt, {acc, stats}}
    else
      case parse_and_validate_row(row, headers, parser, skip_invalid) do
        {:ok, record} ->
          {:cont, {[record | acc], %{stats | parsed: stats.parsed + 1}}}

        {:skip, _reason} ->
          {:cont, {acc, %{stats | skipped: stats.skipped + 1}}}

        {:error, _reason} ->
          {:cont, {acc, %{stats | errors: stats.errors + 1}}}
      end
    end
  end

  defp parse_and_validate_row(row, headers, parser, skip_invalid) do
    row_map = parse_row(row, headers)

    case parser.(row_map) do
      {:ok, record} ->
        {:ok, record}

      {:error, reason} when skip_invalid ->
        {:skip, reason}

      {:error, reason} ->
        {:error, reason}

      # Fallback for parsers that still return nil/records directly
      nil when skip_invalid ->
        {:skip, :parser_returned_nil}

      nil ->
        {:error, :parser_returned_nil}

      record ->
        {:ok, record}
    end
  rescue
    error ->
      Logger.warning("Row parsing failed: #{inspect(error)}")
      if skip_invalid, do: {:skip, error}, else: {:error, error}
  end
end
