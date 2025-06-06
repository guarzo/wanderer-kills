defmodule WandererKills.External.ESI.Client do
  @moduledoc """
  ESI (EVE Swagger Interface) API client for WandererKills.

  This module handles fetching data directly from the EVE Swagger
  Interface (ESI) API, including ship type data and killmail details.

  ## Features

  - Fetches ship group and type data from ESI API
  - Fetches killmail data using killmail ID and hash
  - Handles batch processing with configurable concurrency
  - Integrates with existing cache infrastructure
  - Supports partial updates by ship group

  ## Usage

  ```elixir
  # Use the behaviour interface for ship types
  alias WandererKills.External.ESI.Client

  case Client.update() do
    :ok -> Logger.info("ESI update successful")
    {:error, reason} -> Logger.error("ESI update failed: \#{inspect(reason)}")
  end

  # Fetch a specific killmail
  case Client.get_killmail(killmail_id, killmail_hash) do
    {:ok, killmail} -> Logger.info("Killmail fetched successfully")
    {:error, reason} -> Logger.error("Failed to fetch killmail: \#{inspect(reason)}")
  end
  ```
  """

  use WandererKills.Data.Behaviours.ShipTypeSource

  require Logger
  alias WandererKills.Constants
  alias WandererKills.Infrastructure.Config
  alias WandererKills.Infrastructure.BatchProcessor
  alias WandererKills.TaskSupervisor
  alias WandererKills.Cache
  alias WandererKills.Infrastructure.Error

  # Default ship group IDs that contain ship types
  @ship_group_ids [6, 7, 9, 11, 16, 17, 23]

  defp http_client, do: WandererKills.Infrastructure.Config.http_client()

  @doc """
  Base URL for ESI API.
  """
  def base_url do
    Config.esi(:base_url)
  end

  @doc """
  Ensures ESI data is cached by fetching it from the API if not present.
  """
  @spec ensure_cached(atom(), integer()) :: :ok | {:error, term()}
  def ensure_cached(:group, group_id) do
    case Cache.get_group_info(group_id) do
      {:ok, _group_info} ->
        :ok

      {:error, :not_found} ->
        fetch_and_cache_group_info(group_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def ensure_cached(:type, type_id) do
    case Cache.get_type_info(type_id) do
      {:ok, _type_info} ->
        :ok

      {:error, :not_found} ->
        fetch_and_cache_type_info(type_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def ensure_cached(:character, character_id) do
    case Cache.get_character_info(character_id) do
      {:ok, _character_info} ->
        :ok

      {:error, :not_found} ->
        fetch_and_cache_character_info(character_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def ensure_cached(:corporation, corporation_id) do
    case Cache.get_corporation_info(corporation_id) do
      {:ok, _corp_info} ->
        :ok

      {:error, :not_found} ->
        fetch_and_cache_corporation_info(corporation_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def ensure_cached(:alliance, alliance_id) do
    case Cache.get_alliance_info(alliance_id) do
      {:ok, _alliance_info} ->
        :ok

      {:error, :not_found} ->
        fetch_and_cache_alliance_info(alliance_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_and_cache_group_info(group_id) do
    url = "#{base_url()}/universe/groups/#{group_id}/"

    case http_client().get_with_rate_limit(url, []) do
      {:ok, %{body: body}} ->
        group_info = %{
          group_id: group_id,
          name: Map.get(body, "name"),
          category_id: Map.get(body, "category_id"),
          published: Map.get(body, "published"),
          types: Map.get(body, "types", [])
        }

        case Cache.set_group_info(group_id, group_info) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch group info for #{group_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_and_cache_type_info(type_id) do
    url = "#{base_url()}/universe/types/#{type_id}/"

    case http_client().get_with_rate_limit(url, []) do
      {:ok, %{body: body}} ->
        type_info = %{
          type_id: type_id,
          name: Map.get(body, "name"),
          description: Map.get(body, "description"),
          group_id: Map.get(body, "group_id"),
          market_group_id: Map.get(body, "market_group_id"),
          mass: Map.get(body, "mass"),
          packaged_volume: Map.get(body, "packaged_volume"),
          portion_size: Map.get(body, "portion_size"),
          published: Map.get(body, "published"),
          radius: Map.get(body, "radius"),
          volume: Map.get(body, "volume")
        }

        case Cache.set_type_info(type_id, type_info) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch type info for #{type_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_and_cache_character_info(character_id) do
    url = "#{base_url()}/characters/#{character_id}/"

    case http_client().get_with_rate_limit(url, []) do
      {:ok, %{body: body}} ->
        character_info = %{
          "character_id" => character_id,
          "name" => Map.get(body, "name"),
          "corporation_id" => Map.get(body, "corporation_id"),
          "alliance_id" => Map.get(body, "alliance_id"),
          "birthday" => Map.get(body, "birthday"),
          "gender" => Map.get(body, "gender"),
          "race_id" => Map.get(body, "race_id"),
          "bloodline_id" => Map.get(body, "bloodline_id"),
          "ancestry_id" => Map.get(body, "ancestry_id"),
          "security_status" => Map.get(body, "security_status")
        }

        case Cache.set_character_info(character_id, character_info) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch character info for #{character_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_and_cache_corporation_info(corporation_id) do
    url = "#{base_url()}/corporations/#{corporation_id}/"

    case http_client().get_with_rate_limit(url, []) do
      {:ok, %{body: body}} ->
        corp_info = %{
          "corporation_id" => corporation_id,
          "name" => Map.get(body, "name"),
          "ticker" => Map.get(body, "ticker"),
          "alliance_id" => Map.get(body, "alliance_id"),
          "ceo_id" => Map.get(body, "ceo_id"),
          "creator_id" => Map.get(body, "creator_id"),
          "date_founded" => Map.get(body, "date_founded"),
          "description" => Map.get(body, "description"),
          "faction_id" => Map.get(body, "faction_id"),
          "home_station_id" => Map.get(body, "home_station_id"),
          "member_count" => Map.get(body, "member_count"),
          "shares" => Map.get(body, "shares"),
          "tax_rate" => Map.get(body, "tax_rate"),
          "url" => Map.get(body, "url"),
          "war_eligible" => Map.get(body, "war_eligible")
        }

        case Cache.set_corporation_info(corporation_id, corp_info) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch corporation info for #{corporation_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_and_cache_alliance_info(alliance_id) do
    url = "#{base_url()}/alliances/#{alliance_id}/"

    case http_client().get_with_rate_limit(url, []) do
      {:ok, %{body: body}} ->
        alliance_info = %{
          "alliance_id" => alliance_id,
          "name" => Map.get(body, "name"),
          "ticker" => Map.get(body, "ticker"),
          "creator_corporation_id" => Map.get(body, "creator_corporation_id"),
          "creator_id" => Map.get(body, "creator_id"),
          "date_founded" => Map.get(body, "date_founded"),
          "executor_corporation_id" => Map.get(body, "executor_corporation_id"),
          "faction_id" => Map.get(body, "faction_id")
        }

        case Cache.set_alliance_info(alliance_id, alliance_info) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch alliance info for #{alliance_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches a killmail from the ESI API using killmail ID and hash.

  ## Parameters
  - `killmail_id` - The killmail ID (integer)
  - `killmail_hash` - The killmail hash (string)

  ## Returns
  - `{:ok, killmail}` - Successfully fetched killmail data
  - `{:error, reason}` - Failed to fetch killmail

  ## Example
  ```elixir
  case WandererKills.External.ESI.Client.get_killmail(123456, "abc123def") do
    {:ok, killmail} ->
      # Process the killmail data
      IO.inspect(killmail)
    {:error, reason} ->
      Logger.error("Failed to fetch killmail: \#{inspect(reason)}")
  end
  ```
  """
  @spec get_killmail(integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_killmail(killmail_id, killmail_hash) do
    url = "#{base_url()}/killmails/#{killmail_id}/#{killmail_hash}/"

    case http_client().get_with_rate_limit(url, []) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

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
    # via Cache.get_type_info when we fetch type details

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

    opts = [
      max_concurrency: Constants.concurrency(:default),
      timeout: :timer.seconds(30)
    ]

    batch_opts =
      Keyword.merge(opts, supervisor: TaskSupervisor, description: "ship group processing")

    case BatchProcessor.process_parallel(group_ids, &fetch_group_types/1, batch_opts) do
      {:ok, _results} ->
        Logger.info("Successfully processed all ship groups from ESI")
        :ok

      {:partial, _results, failures} ->
        Logger.error("Some ship groups failed to process: #{inspect(failures)}")

        {:error,
         Error.esi_error(:batch_processing_failed, "Some ship groups failed to process", true)}

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
    opts = [
      max_concurrency: Constants.concurrency(:default),
      timeout: :timer.seconds(30)
    ]

    batch_opts =
      Keyword.merge(opts, supervisor: TaskSupervisor, description: "group info fetching")

    case BatchProcessor.process_parallel(group_ids, &fetch_group_info/1, batch_opts) do
      {:ok, _results} ->
        collect_type_ids_from_groups(group_ids)

      {:partial, _results, _failures} ->
        # Even if some group fetches fail, we can proceed with what we have
        collect_type_ids_from_groups(group_ids)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_group_info(group_id) do
    case ensure_cached(:group, group_id) do
      :ok ->
        Logger.debug("Successfully fetched group info for group #{group_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch group info for group #{group_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_group_types(group_id) do
    case Cache.get_group_info(group_id) do
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
    opts = [
      max_concurrency: Constants.concurrency(:default),
      timeout: :timer.seconds(30)
    ]

    batch_opts =
      Keyword.merge(opts, supervisor: TaskSupervisor, description: "ship type details fetching")

    case BatchProcessor.process_parallel(type_ids, &fetch_ship_type_details/1, batch_opts) do
      {:ok, _results} -> :ok
      # Partial success is acceptable
      {:partial, _results, _failures} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_ship_type_details(type_id) do
    case ensure_cached(:type, type_id) do
      :ok ->
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
      case Cache.get_type_info(type_id) do
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
    case Cache.get_group_info(group_id) do
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
