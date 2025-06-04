defmodule WandererKills.Data.ShipTypeEsiUpdater do
  @moduledoc """
  Handles updating ship type data by fetching from the EVE Swagger Interface (ESI).

  This module focuses solely on ESI-based ship type data management:
  - Fetches ship group information from ESI
  - Retrieves individual ship type data from ESI
  - Caches fetched data in the ESI cache
  - Handles batch processing with configurable concurrency

  ## Usage

  ```elixir
  # Update ship types from ESI
  case WandererKills.Data.ShipTypeEsiUpdater.update_from_esi() do
    :ok -> Logger.info("Ship types updated from ESI")
    {:error, _reason} -> Logger.error("ESI update failed")
  end

  # Update specific ship groups
  WandererKills.Data.ShipTypeEsiUpdater.update_ship_groups([6, 7, 9])
  ```
  """

  require Logger
  alias WandererKills.Core.Shared.Concurrency
  alias WandererKills.TaskSupervisor
  alias WandererKills.Esi.Cache, as: EsiCache

  # Ship group IDs that contain ship types
  @ship_group_ids [6, 7, 9, 11, 16, 17, 23]

  @config Application.compile_env(:wanderer_kills, :ship_type_updater, %{})

  @doc """
  Updates ship types by fetching data from ESI.

  This function processes all known ship groups and fetches type information
  for each ship type within those groups.

  ## Returns
  - `:ok` - If update completed successfully
  - `{:error, reason}` - If update failed

  ## Examples

  ```elixir
  case update_from_esi() do
    :ok -> Logger.info("ESI update successful")
    {:error, :batch_processing_failed} -> Logger.error("Some types failed to process")
    {:error, _reason} -> Logger.error("ESI update failed")
  end
  ```
  """
  @spec update_from_esi() :: :ok | {:error, term()}
  def update_from_esi do
    Logger.info("Starting ship type update from ESI")

    case update_ship_groups(@ship_group_ids) do
      :ok ->
        Logger.info("Ship type update from ESI completed successfully")
        :ok

      {:error, reason} ->
        Logger.error("Failed to update ship types from ESI: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Updates ship types for specific ship groups.

  ## Parameters
  - `group_ids` - List of ship group IDs to process

  ## Returns
  - `:ok` - If all groups processed successfully
  - `{:error, reason}` - If processing failed

  ## Examples

  ```elixir
  # Update specific groups
  update_ship_groups([6, 7, 9])

  # Update all known ship groups
  update_ship_groups(ship_group_ids())
  ```
  """
  @spec update_ship_groups([integer()]) :: :ok | {:error, term()}
  def update_ship_groups(group_ids) when is_list(group_ids) do
    Logger.info("Processing #{length(group_ids)} ship groups from ESI")

    opts = [
      max_concurrency: get_config(:max_concurrency),
      timeout: get_config(:task_timeout_ms)
    ]

    case Concurrency.execute_batch_operation(
           TaskSupervisor,
           group_ids,
           &fetch_group_types/1,
           opts
         ) do
      :ok ->
        Logger.info("Successfully processed all ship groups from ESI")
        :ok

      {:error, reason} ->
        Logger.error("Failed to process ship groups from ESI: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches and caches type information for a specific ship type.

  ## Parameters
  - `type_id` - The ship type ID to fetch

  ## Returns
  - `:ok` - If type was fetched and cached successfully
  - `{:error, reason}` - If fetching failed

  ## Examples

  ```elixir
  case fetch_ship_type(587) do
    :ok -> Logger.info("Rifter type cached")
    {:error, :not_found} -> Logger.error("Type not found")
  end
  ```
  """
  @spec fetch_ship_type(integer()) :: :ok | {:error, term()}
  def fetch_ship_type(type_id) when is_integer(type_id) do
    case EsiCache.get_type_info(type_id) do
      {:ok, _type_data} ->
        Logger.debug("Successfully cached ship type #{type_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch ship type #{type_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches and caches information for multiple ship types in parallel.

  ## Parameters
  - `type_ids` - List of ship type IDs to fetch

  ## Returns
  - `:ok` - If all types processed successfully
  - `{:error, reason}` - If processing failed
  """
  @spec fetch_ship_types([integer()]) :: :ok | {:error, term()}
  def fetch_ship_types(type_ids) when is_list(type_ids) do
    Logger.info("Fetching #{length(type_ids)} ship types from ESI")

    opts = [
      max_concurrency: get_config(:max_concurrency),
      timeout: get_config(:task_timeout_ms)
    ]

    case Concurrency.execute_batch_operation(TaskSupervisor, type_ids, &fetch_ship_type/1, opts) do
      :ok ->
        Logger.info("Successfully fetched all #{length(type_ids)} ship types")
        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch ship types: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists the default ship group IDs that contain ship types.

  ## Returns
  List of ship group IDs

  ## Examples

  ```elixir
  groups = ship_group_ids()
  # => [6, 7, 9, 11, 16, 17, 23]
  ```
  """
  @spec ship_group_ids() :: [integer()]
  def ship_group_ids, do: @ship_group_ids

  @doc """
  Gets the current configuration for ESI operations.

  ## Parameters
  - `key` - Configuration key to retrieve

  ## Returns
  Configuration value

  ## Examples

  ```elixir
  max_concurrent = get_config(:max_concurrency)
  timeout = get_config(:task_timeout_ms)
  ```
  """
  @spec get_config(:max_concurrency | :task_timeout_ms) :: pos_integer()
  def get_config(key) do
    Map.get(@config, key, get_default_config(key))
  end

  # Private functions

  @spec fetch_group_types(integer()) :: :ok | {:error, term()}
  defp fetch_group_types(group_id) when is_integer(group_id) do
    Logger.debug("Fetching types for ship group #{group_id}")

    case EsiCache.get_group_info(group_id) do
      {:ok, %{types: type_ids}} when is_list(type_ids) ->
        Logger.debug("Found #{length(type_ids)} types in group #{group_id}")
        fetch_ship_types(type_ids)

      {:error, reason} ->
        Logger.error("Failed to fetch group #{group_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec get_default_config(:max_concurrency | :task_timeout_ms) :: pos_integer()
  defp get_default_config(:max_concurrency), do: 10
  defp get_default_config(:task_timeout_ms), do: 30_000
end
