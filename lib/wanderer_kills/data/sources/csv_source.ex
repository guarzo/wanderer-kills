defmodule WandererKills.Data.Sources.CsvSource do
  @moduledoc """
  CSV-based ship type data source implementation.

  This module implements the ShipTypeSource behaviour for downloading and
  processing EVE ship type data from CSV files provided by fuzzwork.co.uk.

  ## Purpose

  This source is intended for **initial data seeding and offline processing**.
  It does NOT populate the ESI cache to avoid conflicts with live ESI data
  that has a different structure and comes from the live EVE API.

  ## Features

  - Downloads CSV files from EVE DB dumps
  - Parses ship type and group data from CSV format
  - Processes ship data for initial seeding or offline analysis
  - Handles file validation and error recovery

  ## Usage vs EsiSource

  - **CsvSource**: Use for initial data seeding, bulk imports, or offline processing
  - **EsiSource**: Use for live ESI cache population with current EVE API data

  These sources have different data structures and should not be mixed in the
  same cache namespace.

  ## Usage

  ```elixir
  # Use for initial data processing (does not populate ESI cache)
  alias WandererKills.Data.Sources.CsvSource

  case CsvSource.update() do
    :ok -> Logger.info("CSV processing successful")
    {:error, reason} -> Logger.error("CSV processing failed: {inspect(reason)}")
  end

  # Or call individual steps
  {:ok, file_paths} = CsvSource.download()
  {:ok, ship_types} = CsvSource.parse(file_paths) # Returns processed data, doesn't cache to ESI
  ```
  """

  use WandererKills.Data.Behaviours.ShipTypeSource

  require Logger
  alias WandererKills.Infrastructure.BatchProcessor
  alias WandererKills.ShipTypes.CSVHelpers
  alias WandererKills.Infrastructure.Error
  # Note: Cache.Base and Cache.Key removed since CSV source no longer caches to ESI

  @eve_db_dump_url "https://www.fuzzwork.co.uk/dump/latest"
  @required_files ["invGroups.csv", "invTypes.csv"]

  @impl true
  def source_name, do: "CSV"

  @impl true
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

  @impl true
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

    case WandererKills.Http.Utils.fetch_raw(url, raw: true) do
      {:ok, body} ->
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

  defp build_ship_types(types, groups) do
    # Get ship group IDs from configuration
    ship_group_ids = [6, 7, 9, 11, 16, 17, 23]

    types
    |> Enum.filter(&(&1.group_id in ship_group_ids))
    |> Enum.map(fn type ->
      group = Enum.find(groups, &(&1.group_id == type.group_id))
      group_name = if group, do: group.name, else: "Unknown"
      Map.put(type, :group_name, group_name)
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Cache ship types to ESI cache for immediate availability
  defp cache_ship_types(ship_types) when is_list(ship_types) do
    Logger.info("CSV source processed #{length(ship_types)} ship types successfully")
    Logger.info("Caching ship types to ESI cache for enrichment")

    # Cache each ship type individually
    cached_count =
      ship_types
      |> Enum.map(fn ship_type ->
        type_data = %{
          "type_id" => ship_type.type_id,
          "name" => ship_type.name,
          "group_id" => ship_type.group_id,
          "group_name" => ship_type.group_name,
          "published" => Map.get(ship_type, :published, true),
          "description" => Map.get(ship_type, :description, ""),
          "mass" => Map.get(ship_type, :mass, 0.0),
          "volume" => Map.get(ship_type, :volume, 0.0),
          "capacity" => Map.get(ship_type, :capacity, 0.0)
        }

        case WandererKills.Cache.set_type_info(ship_type.type_id, type_data) do
          :ok ->
            1

          {:error, reason} ->
            Logger.warning("Failed to cache ship type #{ship_type.type_id}: #{inspect(reason)}")
            0
        end
      end)
      |> Enum.sum()

    Logger.info("Successfully cached #{cached_count}/#{length(ship_types)} ship types")
    :ok
  end

  defp process_csv_data(types_path, groups_path) do
    with {:ok, types} <- CSVHelpers.read_file(types_path, &CSVHelpers.parse_ship_type/1),
         {:ok, groups} <- CSVHelpers.read_file(groups_path, &CSVHelpers.parse_ship_group/1) do
      # Filter for ship types and enrich with group names
      ship_types = build_ship_types(types, groups)

      handle_ship_types_result(ship_types)
    end
  end

  defp handle_ship_types_result(ship_types) do
    if Enum.empty?(ship_types) do
      {:error,
       Error.ship_types_error(
         :no_ship_types,
         "No ship types found in CSV data for configured ship groups"
       )}
    else
      # Cache the ship types as part of the parse step
      cache_ship_types(ship_types)
      Logger.info("Successfully parsed and cached #{length(ship_types)} ship types from CSV")
      {:ok, ship_types}
    end
  end
end
