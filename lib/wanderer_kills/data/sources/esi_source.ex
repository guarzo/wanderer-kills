defmodule WandererKills.Data.Sources.EsiSource do
  @moduledoc """
  ESI-based ship type data source implementation.

  This module implements the ShipTypeSource behaviour for fetching ship type
  data directly from the EVE Swagger Interface (ESI) API.

  ## Features

  - Fetches ship group and type data from ESI API
  - Handles batch processing with configurable concurrency
  - Integrates with existing ESI cache infrastructure
  - Supports partial updates by ship group

  ## Usage

  ```elixir
  # Use the behaviour interface
  alias WandererKills.Data.Sources.EsiSource

  case EsiSource.update() do
    :ok -> Logger.info("ESI update successful")
    {:error, reason} -> Logger.error("ESI update failed: {inspect(reason)}")
  end

  # Update specific ship groups
  case EsiSource.update(group_ids: [6, 7, 9]) do
    :ok -> Logger.info("Partial ESI update successful")
    {:error, reason} -> Logger.error("Partial ESI update failed: {inspect(reason)}")
  end
  ```
  """

  use WandererKills.Data.Behaviours.ShipTypeSource

  require Logger
  alias WandererKills.Config
  alias WandererKills.Core.Shared.Concurrency
  alias WandererKills.TaskSupervisor
  alias WandererKills.Cache.Specialized.EsiCache

  # Default ship group IDs that contain ship types
  @ship_group_ids [6, 7, 9, 11, 16, 17, 23]

  @impl true
  def source_name, do: "ESI"

  @impl true
  def download(opts \\ []) do
    Logger.info("Fetching ship group data from ESI API")

    group_ids = Keyword.get(opts, :group_ids, @ship_group_ids)
    Logger.info("Processing #{length(group_ids)} ship groups from ESI")

    case fetch_group_type_ids(group_ids) do
      {:ok, type_ids} ->
        Logger.info("Successfully fetched #{length(type_ids)} ship type IDs from ESI")
        {:ok, type_ids}

      {:error, reason} ->
        Logger.error("Failed to fetch ship group data from ESI: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def parse(ship_groups) when is_list(ship_groups) do
    # Parse ship group data into ship types
    # Note: Individual ship types are automatically cached during ESI fetch
    # via EsiCache.get_type_info when we fetch type details

    # Extract all type IDs from the groups
    type_ids =
      ship_groups
      |> Enum.flat_map(fn group ->
        case group do
          %{types: types} when is_list(types) -> types
          _ -> []
        end
      end)
      |> Enum.uniq()

    # Collect the cached ship type data
    ship_types = collect_ship_types(type_ids)

    Logger.info("Parsed #{length(ship_types)} ship types from #{length(ship_groups)} groups")
    {:ok, ship_types}
  end

  # Public convenience functions

  @doc """
  Updates ship types for specific ship groups.

  ## Parameters
  - `group_ids` - List of ship group IDs to process

  ## Returns
  - `:ok` - If all groups processed successfully
  - `{:error, reason}` - If processing failed
  """
  @spec update_ship_groups([integer()]) :: :ok | {:error, term()}
  def update_ship_groups(group_ids) when is_list(group_ids) do
    Logger.info("Processing #{length(group_ids)} ship groups from ESI")

    concurrency_config = Config.concurrency()

    opts = [
      max_concurrency: concurrency_config.max_concurrent,
      timeout: :timer.seconds(30)
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
  Gets the default ship group IDs.
  """
  @spec ship_group_ids() :: [integer()]
  def ship_group_ids, do: @ship_group_ids

  # Private helper functions

  defp fetch_group_type_ids(group_ids) do
    # Fetch all group information and collect type IDs
    concurrency_config = Config.concurrency()

    opts = [
      max_concurrency: concurrency_config.max_concurrent,
      timeout: :timer.seconds(30)
    ]

    case Concurrency.execute_batch_operation(
           TaskSupervisor,
           group_ids,
           &fetch_group_info/1,
           opts
         ) do
      :ok ->
        collect_type_ids_from_groups(group_ids)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_group_info(group_id) do
    case EsiCache.get_group_info(group_id) do
      {:ok, _group_info} ->
        Logger.debug("Successfully fetched group info for group #{group_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch group info for group #{group_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_group_types(group_id) do
    case EsiCache.get_group_info(group_id) do
      {:ok, group_info} ->
        handle_group_info(group_id, group_info)

      {:error, reason} ->
        Logger.error("Failed to fetch group #{group_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_group_info(group_id, %{types: type_ids})
       when is_list(type_ids) and length(type_ids) > 0 do
    Logger.debug("Fetching #{length(type_ids)} types for group #{group_id}")
    fetch_ship_types(type_ids)
  end

  defp handle_group_info(group_id, _group_info) do
    Logger.debug("Group #{group_id} has no types or unexpected format")
    :ok
  end

  defp fetch_ship_types(type_ids) when is_list(type_ids) do
    concurrency_config = Config.concurrency()

    opts = [
      max_concurrency: concurrency_config.max_concurrent,
      timeout: :timer.seconds(30)
    ]

    Concurrency.execute_batch_operation(
      TaskSupervisor,
      type_ids,
      &fetch_ship_type_details/1,
      opts
    )
  end

  defp fetch_ship_type_details(type_id) do
    case EsiCache.get_type_info(type_id) do
      {:ok, _type_info} ->
        Logger.debug("Successfully fetched ship type #{type_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch ship type #{type_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp collect_ship_types(type_ids) do
    type_ids
    |> Enum.map(fn type_id ->
      case EsiCache.get_type_info(type_id) do
        {:ok, type_info} -> type_info
        {:error, _reason} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp collect_type_ids_from_groups(group_ids) do
    # Collect all type IDs from the groups
    type_ids =
      group_ids
      |> Enum.flat_map(&extract_types_from_group/1)
      |> Enum.uniq()

    {:ok, type_ids}
  end

  defp extract_types_from_group(group_id) do
    case EsiCache.get_group_info(group_id) do
      {:ok, %{types: types}} when is_list(types) -> types
      _ -> []
    end
  end

  # Override the default update pipeline for ESI-specific orchestration
  @impl true
  def update(opts) do
    Logger.info("Starting ship type update from #{source_name()}")

    group_ids = Keyword.get(opts, :group_ids, @ship_group_ids)

    case update_ship_groups(group_ids) do
      :ok ->
        Logger.info("Ship type update from #{source_name()} completed successfully")
        :ok

      {:error, reason} ->
        Logger.error("Ship type update from #{source_name()} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
