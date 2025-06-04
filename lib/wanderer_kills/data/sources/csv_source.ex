defmodule WandererKills.Data.Sources.CsvSource do
  @moduledoc """
  CSV-based ship type data source implementation.

  This module implements the ShipTypeSource behaviour for downloading and
  processing EVE ship type data from CSV files provided by fuzzwork.co.uk.

  ## Features

  - Downloads CSV files from EVE DB dumps
  - Parses ship type and group data from CSV format
  - Caches processed data in the ESI cache
  - Handles file validation and error recovery

  ## Usage

  ```elixir
  # Use the behaviour interface
  alias WandererKills.Data.Sources.CsvSource

  case CsvSource.update() do
    :ok -> Logger.info("CSV update successful")
    {:error, reason} -> Logger.error("CSV update failed: {inspect(reason)}")
  end

  # Or call individual steps
  {:ok, file_paths} = CsvSource.download()
  {:ok, ship_types} = CsvSource.parse(file_paths)
  :ok = CsvSource.cache(ship_types)
  ```
  """

  use WandererKills.Data.Behaviours.ShipTypeSource

  require Logger
  alias WandererKills.Config
  alias WandererKills.Http.Client
  alias WandererKills.Core.Shared.Concurrency
  alias WandererKills.Data.Parsers.CsvUtil
  alias WandererKills.Cache.Base
  alias WandererKills.Cache.Key

  @eve_db_dump_url "https://www.fuzzwork.co.uk/dump/latest"
  @required_files ["invGroups.csv", "invTypes.csv"]

  defp http_client, do: Application.get_env(:wanderer_kills, :http_client, Client)

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

  # Legacy cache function - no longer used but kept for potential future reference
  def cache(ship_types) when is_list(ship_types) do
    Logger.info("Caching #{length(ship_types)} ship types from CSV")

    try do
      Enum.each(ship_types, fn ship ->
        key = Key.type_info_key(ship.type_id)
        :ok = Base.set_value(:esi, key, ship)
      end)

      Logger.info("Successfully cached #{length(ship_types)} ship types")
      :ok
    rescue
      error ->
        Logger.error("Failed to cache ship types: #{inspect(error)}")
        {:error, :cache_failed}
    end
  end

  # Private helper functions

  defp get_data_directory do
    Config.concurrency().batch_size
    |> then(fn _ -> Path.join([:code.priv_dir(:wanderer_kills), "data"]) end)
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
    _concurrency_config = Config.concurrency()

    task_fn = fn file_name ->
      Task.async(fn -> download_single_file(file_name, data_dir) end)
    end

    case Concurrency.execute_parallel_tasks(
           file_names,
           task_fn,
           :timer.minutes(5)
         ) do
      :ok ->
        Logger.info("Successfully downloaded all CSV files")
        :ok

      {:error, reason} ->
        Logger.error("Failed to download CSV files: #{inspect(reason)}")
        {:error, :download_failed}
    end
  end

  defp download_single_file(file_name, data_dir) do
    url = "#{@eve_db_dump_url}/#{file_name}"
    download_path = Path.join(data_dir, file_name)

    Logger.info("Downloading CSV file", file: file_name, url: url, path: download_path)

    case http_client().get_with_rate_limit(url, raw: true) do
      {:ok, %{body: body}} when is_binary(body) ->
        case File.write(download_path, body) do
          :ok ->
            Logger.info("Successfully downloaded #{file_name}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to write file #{file_name}: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, response} ->
        Logger.error("Unexpected response format for #{file_name}: #{inspect(response)}")
        {:error, :unexpected_response_format}

      {:error, reason} ->
        Logger.error("Failed to download file #{file_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_csv_files(file_paths) do
    types_path = Enum.find(file_paths, &String.ends_with?(&1, "invTypes.csv"))
    groups_path = Enum.find(file_paths, &String.ends_with?(&1, "invGroups.csv"))

    case {types_path, groups_path} do
      {nil, _} -> {:error, :missing_types_file}
      {_, nil} -> {:error, :missing_groups_file}
      {types, groups} -> {:ok, {types, groups}}
    end
  end

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

  defp cache_ship_types(ship_types) when is_list(ship_types) do
    try do
      Enum.each(ship_types, fn ship ->
        key = Key.type_info_key(ship.type_id)
        :ok = Base.set_value(:esi, key, ship)
      end)

      Logger.info("Successfully cached #{length(ship_types)} ship types")
      :ok
    rescue
      error ->
        Logger.error("Failed to cache ship types: #{inspect(error)}")
        {:error, :cache_failed}
    end
  end

  defp process_csv_data(types_path, groups_path) do
    with {:ok, types} <- CsvUtil.read_rows(types_path, &parse_type_row/1),
         {:ok, groups} <- CsvUtil.read_rows(groups_path, &parse_group_row/1) do
      # Filter for ship types and enrich with group names
      ship_types = build_ship_types(types, groups)

      handle_ship_types_result(ship_types)
    end
  end

  defp handle_ship_types_result(ship_types) do
    if Enum.empty?(ship_types) do
      {:error, :no_ship_types}
    else
      # Cache the ship types as part of the parse step
      case cache_ship_types(ship_types) do
        :ok ->
          Logger.info("Successfully parsed and cached #{length(ship_types)} ship types from CSV")

          {:ok, ship_types}

        {:error, reason} ->
          Logger.error("Parsing succeeded but caching failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
