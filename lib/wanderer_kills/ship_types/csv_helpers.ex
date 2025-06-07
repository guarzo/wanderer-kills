defmodule WandererKills.ShipTypes.CSVHelpers do
  @moduledoc """
  CSV-based ship type data processing helpers.

  This module provides functionality for downloading and processing EVE ship type
  data from CSV files provided by fuzzwork.co.uk. It replaces the previous
  data source architecture with direct ship type domain functionality.

  ## Purpose

  This module is intended for **initial data seeding and offline processing**.
  It does NOT populate the ESI cache to avoid conflicts with live ESI data
  that has a different structure and comes from the live EVE API.

  ## Features

  - Downloads CSV files from EVE DB dumps
  - Parses ship type and group data from CSV format
  - Processes ship data for initial seeding or offline analysis
  - Handles file validation and error recovery

  ## Usage

  ```elixir
  # Download and process CSV data
  case CSVHelpers.update() do
    :ok -> Logger.info("CSV processing successful")
    {:error, reason} -> Logger.error("CSV processing failed")
  end

  # Or call individual steps
  {:ok, file_paths} = CSVHelpers.download()
  {:ok, ship_types} = CSVHelpers.parse(file_paths)
  ```
  """

  require Logger
  alias WandererKills.Core.BatchProcessor
  alias WandererKills.Core.Error

  @eve_db_dump_url "https://www.fuzzwork.co.uk/dump/latest"
  @required_files ["invGroups.csv", "invTypes.csv"]

  @doc """
  Complete update pipeline: download -> parse.

  ## Parameters
  - `opts` - Options passed to the download step

  ## Returns
  - `:ok` - Complete pipeline succeeded
  - `{:error, reason}` - Pipeline failed at some step
  """
  @spec update(keyword()) :: :ok | {:error, term()}
  def update(opts \\ []) do
    Logger.info("Starting ship type update from CSV")

    with {:ok, raw_data} <- download(opts),
         {:ok, _parsed_data} <- parse(raw_data) do
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
  @spec download(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def download(opts \\ []) do
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
  @spec parse([String.t()]) :: {:ok, [map()]} | {:error, term()}
  def parse(file_paths) when is_list(file_paths) do
    Logger.info("Parsing ship type data from CSV files")

    case find_csv_files(file_paths) do
      {:ok, {types_path, groups_path}} ->
        process_csv_data(types_path, groups_path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

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

    with {:ok, types_data} <- parse_csv_file(types_path),
         {:ok, groups_data} <- parse_csv_file(groups_path) do
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

  defp parse_csv_file(file_path) do
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

    # Build group lookup map
    groups_map =
      groups
      |> Enum.reduce(%{}, fn row, acc ->
        case {Map.get(row, "groupID"), Map.get(row, "groupName")} do
          {group_id_str, group_name} when is_binary(group_id_str) and is_binary(group_name) ->
            case Integer.parse(group_id_str) do
              {group_id, ""} -> Map.put(acc, group_id, group_name)
              _ -> acc
            end

          _ ->
            acc
        end
      end)

    # Filter and process ship types
    types
    |> Enum.filter(fn row ->
      case Map.get(row, "groupID") do
        group_id_str when is_binary(group_id_str) ->
          case Integer.parse(group_id_str) do
            {group_id, ""} -> group_id in ship_group_ids
            _ -> false
          end

        _ ->
          false
      end
    end)
    |> Enum.map(fn row ->
      type_id = parse_integer(Map.get(row, "typeID"))
      group_id = parse_integer(Map.get(row, "groupID"))

      %{
        type_id: type_id,
        name: Map.get(row, "typeName", "Unknown"),
        group_id: group_id,
        group_name: Map.get(groups_map, group_id, "Unknown Group")
      }
    end)
    |> Enum.reject(&is_nil(&1.type_id))
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(int) when is_integer(int), do: int
end
