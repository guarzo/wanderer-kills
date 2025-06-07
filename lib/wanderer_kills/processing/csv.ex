defmodule WandererKills.Processing.CSV do
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
  alias WandererKills.Infrastructure.Error

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
  # Ship Type Update Pipeline
  # ============================================================================

  @eve_db_dump_url "https://www.fuzzwork.co.uk/dump/latest"
  @required_files ["invGroups.csv", "invTypes.csv"]

  @doc """
  Complete ship type update pipeline: download -> parse -> process.

  ## Parameters
  - `opts` - Options passed to the download step

  ## Returns
  - `:ok` - Complete pipeline succeeded
  - `{:error, reason}` - Pipeline failed at some step
  """
  @spec update_ship_types(keyword()) :: :ok | {:error, Error.t()}
  def update_ship_types(opts \\ []) do
    Logger.info("Starting ship type update from CSV")

    with {:ok, raw_data} <- download_csv_files(opts),
         {:ok, _parsed_data} <- parse_ship_type_csvs(raw_data) do
      Logger.info("Ship type update from CSV completed successfully")
      :ok
    else
      {:error, reason} ->
        Logger.error("Ship type update from CSV failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Downloads CSV files for ship type data.

  ## Parameters
  - `opts` - Download options including `:force_download`

  ## Returns
  - `{:ok, file_paths}` - List of downloaded file paths
  - `{:error, reason}` - Download failed
  """
  @spec download_csv_files(keyword()) :: {:ok, [String.t()]} | {:error, Error.t()}
  def download_csv_files(opts \\ []) do
    Logger.info("Downloading CSV files for ship type data")

    data_dir = get_data_directory()
    File.mkdir_p!(data_dir)

    force_download = Keyword.get(opts, :force_download, false)

    missing_files =
      if force_download do
        @required_files
      else
        get_missing_files(data_dir)
      end

    if Enum.empty?(missing_files) do
      Logger.info("All required CSV files are present")
      {:ok, get_file_paths(data_dir)}
    else
      Logger.info("Downloading #{length(missing_files)} CSV files: #{inspect(missing_files)}")

      case download_files(missing_files, data_dir) do
        :ok -> {:ok, get_file_paths(data_dir)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Parses CSV files into ship type data.

  ## Parameters
  - `file_paths` - List of CSV file paths to parse

  ## Returns
  - `{:ok, ship_types}` - Parsed ship type data
  - `{:error, reason}` - Parsing failed
  """
  @spec parse_ship_type_csvs([String.t()]) :: {:ok, [map()]} | {:error, Error.t()}
  def parse_ship_type_csvs(file_paths) when is_list(file_paths) do
    Logger.info("Parsing ship type data from CSV files")

    case find_csv_files(file_paths) do
      {:ok, {types_path, groups_path}} ->
        process_csv_data(types_path, groups_path)

      {:error, reason} ->
        {:error, reason}
    end
  end

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

  # Ship type CSV download/processing helpers
  defp get_data_directory do
    Path.join([:code.priv_dir(:wanderer_kills), "data"])
  end

  defp get_missing_files(data_dir) do
    @required_files
    |> Enum.reject(fn file ->
      File.exists?(Path.join(data_dir, file))
    end)
  end

  defp get_file_paths(data_dir) do
    @required_files
    |> Enum.map(&Path.join(data_dir, &1))
  end

  defp download_files(file_names, data_dir) do
    alias WandererKills.Core.BatchProcessor

    download_fn = fn file_name -> download_single_file(file_name, data_dir) end

    case BatchProcessor.process_parallel(file_names, download_fn,
           timeout: :timer.minutes(5),
           description: "CSV file downloads"
         ) do
      {:ok, _results} ->
        Logger.info("Successfully downloaded all CSV files")
        :ok

      {:partial, _results, failures} ->
        Logger.error("Some CSV downloads failed: #{inspect(failures)}")

        {:error,
         Error.ship_types_error(:download_failed, "Some CSV file downloads failed", true, %{
           failures: failures
         })}

      {:error, reason} ->
        Logger.error("Failed to download CSV files: #{inspect(reason)}")

        {:error,
         Error.ship_types_error(:download_failed, "Failed to download CSV files", true, %{
           underlying_error: reason
         })}
    end
  end

  defp download_single_file(file_name, data_dir) do
    url = "#{@eve_db_dump_url}/#{file_name}"
    download_path = Path.join(data_dir, file_name)

    Logger.info("Downloading CSV file", file: file_name, url: url, path: download_path)

    case WandererKills.Core.Http.ClientProvider.get().get(url, []) do
      {:ok, %{body: body}} ->
        case File.write(download_path, body) do
          :ok ->
            Logger.info("Successfully downloaded #{file_name}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to write file #{file_name}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to download file #{file_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_csv_files(file_paths) do
    types_path = Enum.find(file_paths, &String.ends_with?(&1, "invTypes.csv"))
    groups_path = Enum.find(file_paths, &String.ends_with?(&1, "invGroups.csv"))

    case {types_path, groups_path} do
      {nil, _} ->
        {:error,
         Error.ship_types_error(
           :missing_types_file,
           "invTypes.csv file not found in provided paths"
         )}

      {_, nil} ->
        {:error,
         Error.ship_types_error(
           :missing_groups_file,
           "invGroups.csv file not found in provided paths"
         )}

      {types, groups} ->
        {:ok, {types, groups}}
    end
  end

  defp process_csv_data(types_path, groups_path) do
    Logger.info("Processing CSV data from files", types: types_path, groups: groups_path)

    with {:ok, types_data} <- parse_csv_file_simple(types_path),
         {:ok, groups_data} <- parse_csv_file_simple(groups_path) do
      ship_types = build_ship_types(types_data, groups_data)
      Logger.info("Successfully processed #{length(ship_types)} ship types from CSV")
      {:ok, ship_types}
    else
      {:error, reason} ->
        Logger.error("Failed to process CSV data: #{inspect(reason)}")

        {:error,
         Error.ship_types_error(:csv_processing_failed, "Failed to process CSV data", false, %{
           underlying_error: reason
         })}
    end
  end

  defp parse_csv_file_simple(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        try do
          # Parse CSV content using simple string splitting
          rows =
            content
            |> String.split("\n")
            |> Enum.reject(&(&1 == ""))
            |> Enum.map(&String.split(&1, ","))

          case rows do
            [headers | data_rows] ->
              parsed_data =
                data_rows
                |> Enum.map(fn row ->
                  headers
                  |> Enum.zip(row)
                  |> Map.new()
                end)

              {:ok, parsed_data}

            [] ->
              {:ok, []}
          end
        rescue
          error ->
            {:error,
             Error.csv_error(:parse_error, "Failed to parse CSV file", %{
               file: file_path,
               error: inspect(error)
             })}
        end

      {:error, reason} ->
        {:error,
         Error.csv_error(:file_read_error, "Failed to read CSV file", %{
           file: file_path,
           reason: reason
         })}
    end
  end

  defp build_ship_types(types, groups) do
    # Get ship group IDs from configuration
    ship_group_ids = [6, 7, 9, 11, 16, 17, 23]

    groups_map = build_groups_map(groups)

    types
    |> filter_ship_types(ship_group_ids)
    |> map_to_ship_types(groups_map)
    |> Enum.reject(&is_nil(&1.type_id))
  end

  @spec build_groups_map([map()]) :: map()
  defp build_groups_map(groups) do
    groups
    |> Enum.reduce(%{}, fn row, acc ->
      build_single_group_entry(row, acc)
    end)
  end

  @spec build_single_group_entry(map(), map()) :: map()
  defp build_single_group_entry(row, acc) do
    group_id_str = Map.get(row, "groupID")
    group_name = Map.get(row, "groupName")

    if valid_group_entry?(group_id_str, group_name) do
      case Integer.parse(group_id_str) do
        {group_id, ""} -> Map.put(acc, group_id, group_name)
        _ -> acc
      end
    else
      acc
    end
  end

  @spec valid_group_entry?(term(), term()) :: boolean()
  defp valid_group_entry?(group_id_str, group_name) do
    is_binary(group_id_str) and is_binary(group_name)
  end

  @spec filter_ship_types([map()], [integer()]) :: [map()]
  defp filter_ship_types(types, ship_group_ids) do
    Enum.filter(types, fn row ->
      ship_type?(row, ship_group_ids)
    end)
  end

  @spec ship_type?(map(), [integer()]) :: boolean()
  defp ship_type?(row, ship_group_ids) do
    group_id_str = Map.get(row, "groupID")

    if is_binary(group_id_str) do
      case Integer.parse(group_id_str) do
        {group_id, ""} -> group_id in ship_group_ids
        _ -> false
      end
    else
      false
    end
  end

  @spec map_to_ship_types([map()], map()) :: [map()]
  defp map_to_ship_types(filtered_types, groups_map) do
    Enum.map(filtered_types, fn row ->
      create_ship_type_entry(row, groups_map)
    end)
  end

  @spec create_ship_type_entry(map(), map()) :: map()
  defp create_ship_type_entry(row, groups_map) do
    type_id = parse_integer_simple(Map.get(row, "typeID"))
    group_id = parse_integer_simple(Map.get(row, "groupID"))

    %{
      type_id: type_id,
      name: Map.get(row, "typeName", "Unknown"),
      group_id: group_id,
      group_name: Map.get(groups_map, group_id, "Unknown Group")
    }
  end

  defp parse_integer_simple(nil), do: nil

  defp parse_integer_simple(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer_simple(int) when is_integer(int), do: int
end
