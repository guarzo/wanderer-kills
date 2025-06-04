defmodule WandererKills.Data.Behaviours.ShipTypeSource do
  @moduledoc """
  Behaviour for ship type data sources.

  This behaviour defines a standard interface for downloading and parsing
  ship type data from different sources (CSV, ESI, etc.). It enables a clean
  separation of concerns and makes it easy to add new data sources.

  Each source handles caching internally as part of the parse step, allowing
  for optimal caching strategies per source type.

  ## Callbacks

  - `download/1` - Downloads or retrieves raw data from the source
  - `parse/1` - Parses the raw data and handles caching

  ## Implementation Example

  ```elixir
  defmodule MyShipTypeSource do
    @behaviour WandererKills.Data.Behaviours.ShipTypeSource

    @impl true
    def download(opts \\ []) do
      # Download logic here
      {:ok, raw_data}
    end

    @impl true
    def parse(raw_data) do
      # Parse logic and caching here
      parsed_data = process(raw_data)
      cache_data(parsed_data)  # Handle caching internally
      {:ok, parsed_data}
    end
  end
  ```
  """

  @type download_opts :: keyword()
  @type raw_data :: term()
  @type parsed_data :: [map()]
  @type cache_result :: :ok | {:error, term()}

  @doc """
  Downloads or retrieves raw ship type data from the source.

  ## Parameters
  - `opts` - Source-specific options for downloading

  ## Returns
  - `{:ok, raw_data}` - Raw data ready for parsing
  - `{:error, reason}` - Download failed

  ## Examples

  ```elixir
  # CSV source might download files
  {:ok, file_paths} = CsvSource.download([])

  # ESI source might fetch group information
  {:ok, group_data} = EsiSource.download(group_ids: [6, 7, 9])
  ```
  """
  @callback download(download_opts()) :: {:ok, raw_data()} | {:error, term()}

  @doc """
  Parses raw data into standardized ship type format and handles caching.

  This step combines parsing and caching for optimal performance. Each source
  can implement caching in the most efficient way for its data flow.

  ## Parameters
  - `raw_data` - Raw data from the download step

  ## Returns
  - `{:ok, parsed_data}` - Structured ship type data (now cached)
  - `{:error, reason}` - Parsing or caching failed

  ## Expected Output Format

  Each parsed ship type should be a map with these keys:
  - `:type_id` - Integer ship type ID
  - `:name` - String ship name
  - `:group_id` - Integer group ID
  - `:group_name` - String group name (optional)
  - Additional fields as needed (mass, volume, etc.)

  ## Examples

  ```elixir
  {:ok, ship_types} = Source.parse(raw_data)
  # ship_types = [
  #   %{type_id: 587, name: "Rifter", group_id: 25, group_name: "Frigate"},
  #   %{type_id: 588, name: "Breacher", group_id: 25, group_name: "Frigate"}
  # ]
  # Data is also cached internally during this step
  ```
  """
  @callback parse(raw_data()) :: {:ok, parsed_data()} | {:error, term()}

  @doc """
  Complete update pipeline: download -> parse (with caching).

  This is a convenience function that runs the full pipeline. The default
  implementation calls the two callbacks in sequence, but implementations
  can override this for custom orchestration.

  ## Parameters
  - `opts` - Options passed to the download step

  ## Returns
  - `:ok` - Complete pipeline succeeded
  - `{:error, reason}` - Pipeline failed at some step
  """
  @callback update(download_opts()) :: cache_result()

  @doc """
  Gets a human-readable name for this source.

  ## Returns
  String identifying the source (e.g., "CSV", "ESI")
  """
  @callback source_name() :: String.t()

  # Provide default implementation for update/1
  defmacro __using__(_opts) do
    quote do
      @behaviour WandererKills.Data.Behaviours.ShipTypeSource

      @doc """
      Default implementation of the update pipeline.
      """
      def update(opts \\ []) do
        require Logger

        Logger.info("Starting ship type update from #{source_name()}")

        with {:ok, raw_data} <- download(opts),
             {:ok, _parsed_data} <- parse(raw_data) do
          Logger.info("Ship type update from #{source_name()} completed successfully")
          :ok
        else
          {:error, reason} ->
            Logger.error("Ship type update from #{source_name()} failed: #{inspect(reason)}")
            {:error, reason}
        end
      end

      # Allow implementations to override the default update/1
      defoverridable update: 1
    end
  end
end
