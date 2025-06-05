defmodule WandererKills.Data.ShipTypeCsvUpdater do
  @moduledoc """
  Handles downloading and updating ship type data from EVE DB CSV dumps.

  This module focuses solely on CSV-based ship type data management:
  - Downloads CSV files from fuzzwork.co.uk
  - Parses ship type data from CSV files
  - Caches parsed data in the ESI cache

  ## Usage

  ```elixir
  # Update ship types from CSV
  case WandererKills.Data.ShipTypeCsvUpdater.update_from_csv() do
    :ok -> Logger.info("Ship types updated from CSV")
    {:error, reason} -> Logger.error("CSV update failed: {inspect(reason)}")
  end

  # Download missing CSV files
  WandererKills.Data.ShipTypeCsvUpdater.download_missing_files()
  ```
  """

  require Logger
  alias WandererKills.Http.ClientProvider
  alias WandererKills.Core.BatchProcessor
  alias WandererKills.Data.Parsers.ShipTypeParser

  @eve_db_dump_url "https://www.fuzzwork.co.uk/dump/latest"
  @required_files ["invGroups.csv", "invTypes.csv"]

  @doc """
  Updates ship types by downloading and processing CSV files.

  ## Returns
  - `:ok` - If update completed successfully
  - `{:error, reason}` - If update failed

  ## Examples

  ```elixir
  case update_from_csv() do
    :ok -> Logger.info("CSV update successful")
    {:error, :download_failed} -> Logger.error("Failed to download CSV files")
    {:error, :parse_failed} -> Logger.error("Failed to parse CSV data")
  end
  ```
  """
  @spec update_from_csv() :: :ok | {:error, term()}
  def update_from_csv do
    Logger.info("Starting ship type update from CSV")

    with :ok <- ensure_csv_files_available(),
         :ok <- process_csv_data() do
      Logger.info("Ship type update from CSV completed successfully")
      :ok
    else
      {:error, reason} ->
        Logger.error("Ship type CSV update failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Downloads missing CSV files if they don't exist locally.

  ## Returns
  - `:ok` - If all files are present or download succeeded
  - `{:error, reason}` - If download failed
  """
  @spec download_missing_files() :: :ok | {:error, term()}
  def download_missing_files do
    data_dir = get_data_directory()
    File.mkdir_p!(data_dir)

    missing_files = get_missing_files(data_dir)

    if Enum.empty?(missing_files) do
      Logger.info("All required CSV files are present")
      :ok
    else
      Logger.info("Missing CSV files: #{inspect(missing_files)}. Downloading...")
      download_files(missing_files)
    end
  end

  @doc """
  Downloads all required CSV files, regardless of whether they exist locally.

  ## Returns
  - `:ok` - If download succeeded
  - `{:error, reason}` - If download failed
  """
  @spec download_all_files() :: :ok | {:error, term()}
  def download_all_files do
    Logger.info("Downloading all CSV files")
    download_files(@required_files)
  end

  @doc """
  Downloads a single CSV file from EVE DB dumps.

  ## Parameters
  - `file_name` - Name of the file to download

  ## Returns
  - `:ok` - If download succeeded
  - `{:error, reason}` - If download failed
  """
  @spec download_file(String.t()) :: :ok | {:error, term()}
  def download_file(file_name) when is_binary(file_name) do
    url = "#{@eve_db_dump_url}/#{file_name}"
    download_path = Path.join([get_data_directory(), file_name])

    Logger.info("Downloading CSV file", file: file_name, url: url, path: download_path)

    case ClientProvider.get().get_with_rate_limit(url, raw: true) do
      {:ok, %{body: body}} when is_binary(body) ->
        process_downloaded_content(body, file_name, download_path)

      {:ok, response} ->
        Logger.error("Unexpected response format for #{file_name}: #{inspect(response)}")
        {:error, :unexpected_response_format}

      {:error, reason} ->
        Logger.error("Failed to download file #{file_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists the required CSV files.
  """
  @spec required_files() :: [String.t()]
  def required_files, do: @required_files

  @doc """
  Gets the local data directory path.
  """
  @spec get_data_directory() :: String.t()
  def get_data_directory do
    Path.join([:code.priv_dir(:wanderer_kills), "data"])
  end

  # Private functions

  @spec ensure_csv_files_available() :: :ok | {:error, term()}
  defp ensure_csv_files_available do
    download_missing_files()
  end

  @spec process_csv_data() :: :ok | {:error, term()}
  defp process_csv_data do
    case ShipTypeParser.load_ship_data() do
      {:ok, {ship_types, _groups}} ->
        cache_ship_types(ship_types)
        Logger.info("Successfully processed #{length(ship_types)} ship types from CSV")
        :ok

      {:error, reason} ->
        Logger.error("Failed to load ship data from CSV: #{inspect(reason)}")
        {:error, :parse_failed}
    end
  end

  @spec cache_ship_types([map()]) :: :ok
  defp cache_ship_types(ship_types) do
    Enum.each(ship_types, fn ship ->
      key = WandererKills.Cache.Key.type_info_key(ship.type_id)
      :ok = WandererKills.Cache.Base.set_value(:esi, key, ship)
    end)

    Logger.info("Cached #{length(ship_types)} ship types")
    :ok
  end

  @spec get_missing_files(String.t()) :: [String.t()]
  defp get_missing_files(data_dir) do
    @required_files
    |> Enum.reject(fn file ->
      File.exists?(Path.join(data_dir, file))
    end)
  end

  @spec download_files([String.t()]) :: :ok | {:error, term()}
  defp download_files(file_names) do
    Logger.info("Downloading #{length(file_names)} CSV files")

    case BatchProcessor.process_parallel(file_names, &download_file/1,
           timeout: :timer.minutes(30),
           description: "CSV file downloads"
         ) do
      {:ok, _results} ->
        Logger.info("Successfully downloaded all CSV files")
        :ok

      {:partial, _results, failures} ->
        Logger.error("Some CSV file downloads failed: #{inspect(failures)}")
        {:error, :download_failed}

      {:error, reason} ->
        Logger.error("Failed to download CSV files: #{inspect(reason)}")
        {:error, :download_failed}
    end
  end

  @spec process_downloaded_content(binary(), String.t(), String.t()) :: :ok | {:error, term()}
  defp process_downloaded_content(body, file_name, download_path) do
    # Check if the content is gzipped and decompress if needed
    final_content =
      try do
        decompressed = :zlib.gunzip(body)
        Logger.debug("Decompressed gzipped content for #{file_name}")
        decompressed
      catch
        _ ->
          # If decompression fails, assume it's already plain text
          Logger.debug("Content not gzipped for #{file_name}, using as-is")
          body
      end

    File.write!(download_path, final_content)
    Logger.info("Successfully downloaded and saved #{file_name}")
    :ok
  rescue
    error ->
      Logger.error("Failed to save downloaded file #{file_name}: #{inspect(error)}")
      {:error, :save_failed}
  end
end
