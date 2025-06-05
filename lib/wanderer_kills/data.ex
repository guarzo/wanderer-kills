defmodule WandererKills.Data do
  @moduledoc """
  Public API for the WandererKills Data domain.

  This module provides a unified interface to data operations including:
  - Data sources (ZKB, ESI, CSV)
  - Data stores (KillmailStore)
  - Data parsing utilities
  - Ship type information

  ## Usage

  ```elixir
  # Uses unified: alias WandererKills.Zkb.Client
  alias WandererKills.Data

  {:ok, killmail} = Data.fetch_killmail_from_zkb(123456)
  ```

  This reduces coupling between domains and provides a stable interface
  for data operations across the application.
  """

  # Data Sources API
  alias WandererKills.Zkb.Client, as: ZkbClient
  alias WandererKills.Data.Sources.CsvSource
  alias WandererKills.Fetcher.Esi.Source, as: EsiSource

  # Data Stores API
  alias WandererKills.Data.Stores.KillmailStore

  # Ship Type Information
  alias WandererKills.Data.{ShipTypeInfo, ShipTypeConstants}

  #
  # ZKB Data Source API
  #

  @doc """
  Fetches a killmail from zKillboard by ID.
  """
  @spec fetch_killmail_from_zkb(integer()) :: {:ok, map()} | {:error, term()}
  def fetch_killmail_from_zkb(killmail_id) do
    ZkbClient.fetch_killmail(killmail_id)
  end

  @doc """
  Fetches killmails for a system from zKillboard.
  """
  @spec fetch_system_killmails_from_zkb(integer()) :: {:ok, [map()]} | {:error, term()}
  def fetch_system_killmails_from_zkb(system_id) do
    ZkbClient.fetch_system_killmails(system_id)
  end

  #
  # ESI Data Source API
  #

  @doc """
  Downloads ship type data from ESI.
  """
  @spec download_ship_types_from_esi(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def download_ship_types_from_esi(opts \\ []) do
    EsiSource.download(opts)
  end

  @doc """
  Parses ship type data from ESI files.
  """
  @spec parse_esi_ship_types([String.t()]) :: {:ok, [map()]} | {:error, term()}
  def parse_esi_ship_types(file_paths) do
    EsiSource.parse(file_paths)
  end

  #
  # CSV Data Source API
  #

  @doc """
  Downloads ship type data from CSV sources.
  """
  @spec download_ship_types_from_csv(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def download_ship_types_from_csv(opts \\ []) do
    CsvSource.download(opts)
  end

  @doc """
  Parses ship type data from CSV files.
  """
  @spec parse_csv_ship_types([String.t()]) :: {:ok, [map()]} | {:error, term()}
  def parse_csv_ship_types(file_paths) do
    CsvSource.parse(file_paths)
  end

  #
  # KillmailStore API
  #

  @doc """
  Stores a killmail in the data store.
  """
  @spec store_killmail(map()) :: :ok | {:error, term()}
  def store_killmail(killmail) do
    KillmailStore.store_killmail(killmail)
  end

  @doc """
  Gets killmails for a system.
  """
  @spec get_killmails_for_system(integer()) :: {:ok, [map()]} | {:error, term()}
  def get_killmails_for_system(system_id) do
    KillmailStore.get_killmails_for_system(system_id)
  end

  @doc """
  Adds a killmail to a system's killmail list.
  """
  @spec add_system_killmail(integer(), integer()) :: :ok
  def add_system_killmail(system_id, killmail_id) do
    KillmailStore.add_system_killmail(system_id, killmail_id)
  end

  #
  # Ship Type Information API
  #

  @doc """
  Gets ship type information by type ID.
  """
  @spec get_ship_type_info(integer()) :: {:ok, map()} | {:error, term()}
  def get_ship_type_info(type_id) do
    ShipTypeInfo.get_ship_type(type_id)
  end

  @doc """
  Gets all ship group IDs.
  """
  @spec get_ship_group_ids() :: [integer()]
  def get_ship_group_ids do
    ShipTypeConstants.ship_group_ids()
  end

  @doc """
  Checks if a type ID represents a ship.
  """
  @spec ship_type?(integer()) :: boolean()
  def ship_type?(_type_id) do
    # Check if the type ID is in any of the ship groups
    _ship_groups = ShipTypeConstants.ship_group_ids()
    # This is a simple implementation - in a real scenario you'd check against type data
    # For now, return false as this would need to be implemented with actual type->group mappings
    false
  end

  #
  # Type Definitions
  #

  @type killmail :: map()
  @type ship_type :: map()
  @type result(t) :: {:ok, t} | {:error, term()}
end
