defmodule WandererKills.Data.ShipTypeConstants do
  @moduledoc """
  Constants for ship type data management.

  This module centralizes all ship type related constants to improve
  maintainability and reduce hardcoded values throughout the codebase.

  ## Features

  - Ship group ID definitions
  - EVE DB dump URLs and file names
  - Default configuration values
  - Data directory paths

  ## Usage

  ```elixir
  # Get ship group IDs
  ship_groups = ShipTypeConstants.ship_group_ids()

  # Get EVE DB dump configuration
  base_url = ShipTypeConstants.eve_db_dump_url()
  files = ShipTypeConstants.required_csv_files()

  # Get default settings
  max_concurrent = ShipTypeConstants.default_max_concurrency()
  ```
  """

  @doc """
  Lists all ship group IDs that contain ship types.

  These group IDs represent different categories of ships in EVE Online:
  - 6: Titan
  - 7: Dreadnought
  - 9: Battleship
  - 11: Battlecruiser
  - 16: Cruiser
  - 17: Destroyer
  - 23: Frigate

  ## Returns
  List of ship group IDs

  ## Examples

  ```elixir
  iex> ShipTypeConstants.ship_group_ids()
  [6, 7, 9, 11, 16, 17, 23]
  ```
  """
  @spec ship_group_ids() :: [pos_integer()]
  def ship_group_ids, do: [6, 7, 9, 11, 16, 17, 23]

  @doc """
  Gets the base URL for EVE DB dumps.

  ## Returns
  String URL for downloading EVE DB dump files

  ## Examples

  ```elixir
  iex> ShipTypeConstants.eve_db_dump_url()
  "https://www.fuzzwork.co.uk/dump/latest"
  ```
  """
  @spec eve_db_dump_url() :: String.t()
  def eve_db_dump_url, do: "https://www.fuzzwork.co.uk/dump/latest"

  @doc """
  Lists the required CSV files for ship type data.

  ## Returns
  List of CSV file names required for ship type processing

  ## Examples

  ```elixir
  iex> ShipTypeConstants.required_csv_files()
  ["invGroups.csv", "invTypes.csv"]
  ```
  """
  @spec required_csv_files() :: [String.t()]
  def required_csv_files, do: ["invGroups.csv", "invTypes.csv"]

  @doc """
  Gets the default maximum concurrency for batch operations.

  ## Returns
  Integer representing maximum concurrent tasks

  ## Examples

  ```elixir
  iex> ShipTypeConstants.default_max_concurrency()
  10
  ```
  """
  @spec default_max_concurrency() :: pos_integer()
  def default_max_concurrency, do: 10

  @doc """
  Gets the default task timeout in milliseconds.

  ## Returns
  Integer representing timeout in milliseconds

  ## Examples

  ```elixir
  iex> ShipTypeConstants.default_task_timeout_ms()
  30000
  ```
  """
  @spec default_task_timeout_ms() :: pos_integer()
  def default_task_timeout_ms, do: 30_000

  @doc """
  Gets the data directory path for storing CSV files.

  ## Returns
  String path to the data directory

  ## Examples

  ```elixir
  iex> ShipTypeConstants.data_directory()
  "/path/to/app/priv/data"
  ```
  """
  @spec data_directory() :: String.t()
  def data_directory do
    Path.join([:code.priv_dir(:wanderer_kills), "data"])
  end
end
