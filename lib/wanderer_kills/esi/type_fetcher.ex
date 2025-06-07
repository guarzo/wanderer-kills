defmodule WandererKills.ESI.TypeFetcher do
  @moduledoc """
  ESI Type and Group data fetcher.

  This module handles fetching ship type and group information from the EVE ESI API,
  including type details, group information, and batch operations.
  """

  require Logger
  alias WandererKills.Core.{Config, Error, Cache}
  alias WandererKills.Core.Behaviours.{ESIClient, DataFetcher}

  @behaviour ESIClient
  @behaviour DataFetcher

  # Default ship group IDs that contain ship types
  @ship_group_ids [6, 7, 9, 11, 16, 17, 23]

  @doc """
  Fetches type information from ESI and caches it.
  """
  @impl ESIClient
  def get_type(type_id) when is_integer(type_id) do
    case Cache.get(:esi_cache, {:type, type_id}) do
      {:ok, type_info} ->
        {:ok, type_info}

      {:error, _} ->
        fetch_and_cache_type(type_id)
    end
  end

  @impl ESIClient
  def get_type_batch(type_ids) when is_list(type_ids) do
    Enum.map(type_ids, &get_type/1)
  end

  @doc """
  Fetches group information from ESI and caches it.
  """
  @impl ESIClient
  def get_group(group_id) when is_integer(group_id) do
    case Cache.get(:esi_cache, {:group, group_id}) do
      {:ok, group_info} ->
        {:ok, group_info}

      {:error, _} ->
        fetch_and_cache_group(group_id)
    end
  end

  @impl ESIClient
  def get_group_batch(group_ids) when is_list(group_ids) do
    Enum.map(group_ids, &get_group/1)
  end

  @doc """
  Returns the default ship group IDs.
  """
  def ship_group_ids, do: @ship_group_ids

  @doc """
  Updates ship groups by fetching fresh data from ESI.
  """
  def update_ship_groups(group_ids \\ @ship_group_ids) when is_list(group_ids) do
    Logger.info("Updating ship groups from ESI", group_ids: group_ids)

    results =
      group_ids
      |> Enum.map(&fetch_and_cache_group/1)
      |> Enum.map(fn
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if length(errors) > 0 do
      Logger.error("Failed to update some ship groups",
        error_count: length(errors),
        total_groups: length(group_ids)
      )

      {:error, {:partial_failure, errors}}
    else
      Logger.info("Successfully updated all ship groups")
      :ok
    end
  end

  @doc """
  Fetches types for specific groups and returns parsed ship data.
  """
  def fetch_ship_types_for_groups(group_ids \\ @ship_group_ids) do
    Logger.info("Fetching ship types for groups", group_ids: group_ids)

    with {:ok, groups} <- fetch_groups(group_ids),
         {:ok, ship_types} <- extract_and_fetch_types(groups) do
      {:ok, ship_types}
    else
      {:error, reason} ->
        Logger.error("Failed to fetch ship types: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # DataFetcher behaviour implementations
  @impl DataFetcher
  def fetch({:type, type_id}), do: get_type(type_id)
  def fetch({:group, group_id}), do: get_group(group_id)
  def fetch(_), do: {:error, Error.esi_error(:unsupported, "Unsupported fetch operation")}

  @impl DataFetcher
  def fetch_many(fetch_args) when is_list(fetch_args) do
    Enum.map(fetch_args, &fetch/1)
  end

  @impl DataFetcher
  def supports?({:type, _}), do: true
  def supports?({:group, _}), do: true
  def supports?(_), do: false

  # Not implemented for this module
  @impl ESIClient
  def get_character(_),
    do: {:error, Error.esi_error(:not_implemented, "Character fetching not supported")}

  @impl ESIClient
  def get_character_batch(_),
    do: {:error, Error.esi_error(:not_implemented, "Character fetching not supported")}

  @impl ESIClient
  def get_corporation(_),
    do: {:error, Error.esi_error(:not_implemented, "Corporation fetching not supported")}

  @impl ESIClient
  def get_corporation_batch(_),
    do: {:error, Error.esi_error(:not_implemented, "Corporation fetching not supported")}

  @impl ESIClient
  def get_alliance(_),
    do: {:error, Error.esi_error(:not_implemented, "Alliance fetching not supported")}

  @impl ESIClient
  def get_alliance_batch(_),
    do: {:error, Error.esi_error(:not_implemented, "Alliance fetching not supported")}

  @impl ESIClient
  def get_system(_),
    do: {:error, Error.esi_error(:not_implemented, "System fetching not supported")}

  @impl ESIClient
  def get_system_batch(_),
    do: {:error, Error.esi_error(:not_implemented, "System fetching not supported")}

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp fetch_and_cache_type(type_id) do
    url = "#{esi_base_url()}/universe/types/#{type_id}/"

    case http_client().get(url, default_headers(), []) do
      {:ok, response} ->
        type_info = parse_type_response(type_id, response)

        case Cache.put_with_ttl(:esi_cache, {:type, type_id}, type_info, cache_ttl()) do
          :ok ->
            {:ok, type_info}

          {:error, reason} ->
            {:error, Error.cache_error(:write_failed, "Failed to cache type", %{reason: reason})}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch type #{type_id}: #{inspect(reason)}")

        {:error,
         Error.esi_error(:api_error, "Failed to fetch type from ESI", %{
           type_id: type_id,
           reason: reason
         })}
    end
  end

  defp fetch_and_cache_group(group_id) do
    url = "#{esi_base_url()}/universe/groups/#{group_id}/"

    case http_client().get(url, default_headers(), []) do
      {:ok, response} ->
        group_info = parse_group_response(group_id, response)

        case Cache.put_with_ttl(:esi_cache, {:group, group_id}, group_info, cache_ttl()) do
          :ok ->
            {:ok, group_info}

          {:error, reason} ->
            {:error, Error.cache_error(:write_failed, "Failed to cache group", %{reason: reason})}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch group #{group_id}: #{inspect(reason)}")

        {:error,
         Error.esi_error(:api_error, "Failed to fetch group from ESI", %{
           group_id: group_id,
           reason: reason
         })}
    end
  end

  defp fetch_groups(group_ids) do
    Logger.debug("Fetching groups from ESI", group_ids: group_ids)

    results = Enum.map(group_ids, &get_group/1)

    errors = Enum.filter(results, &match?({:error, _}, &1))
    successes = Enum.filter(results, &match?({:ok, _}, &1))

    if length(errors) > 0 do
      Logger.error("Failed to fetch some groups",
        error_count: length(errors),
        success_count: length(successes)
      )

      {:error, {:partial_failure, errors}}
    else
      groups = Enum.map(successes, fn {:ok, group} -> group end)
      {:ok, groups}
    end
  end

  defp extract_and_fetch_types(groups) do
    Logger.debug("Extracting type IDs from groups")

    type_ids =
      groups
      |> Enum.flat_map(fn group -> Map.get(group, "types", []) end)
      |> Enum.uniq()

    Logger.debug("Fetching types", type_count: length(type_ids))

    results = Enum.map(type_ids, &get_type/1)

    errors = Enum.filter(results, &match?({:error, _}, &1))
    successes = Enum.filter(results, &match?({:ok, _}, &1))

    if length(errors) > 0 do
      Logger.error("Failed to fetch some types",
        error_count: length(errors),
        success_count: length(successes)
      )

      {:error, {:partial_failure, errors}}
    else
      types = Enum.map(successes, fn {:ok, type} -> type end)
      {:ok, types}
    end
  end

  defp parse_type_response(type_id, %{body: body}) do
    %{
      "type_id" => type_id,
      "name" => Map.get(body, "name"),
      "description" => Map.get(body, "description"),
      "group_id" => Map.get(body, "group_id"),
      "market_group_id" => Map.get(body, "market_group_id"),
      "mass" => Map.get(body, "mass"),
      "packaged_volume" => Map.get(body, "packaged_volume"),
      "portion_size" => Map.get(body, "portion_size"),
      "published" => Map.get(body, "published"),
      "radius" => Map.get(body, "radius"),
      "volume" => Map.get(body, "volume")
    }
  end

  defp parse_group_response(group_id, %{body: body}) do
    %{
      "group_id" => group_id,
      "name" => Map.get(body, "name"),
      "category_id" => Map.get(body, "category_id"),
      "published" => Map.get(body, "published"),
      "types" => Map.get(body, "types", [])
    }
  end

  defp esi_base_url, do: Config.service_url(:esi)
  defp cache_ttl, do: Config.cache_ttl(:esi)
  defp http_client, do: Config.http_client()

  defp default_headers do
    [
      {"User-Agent", "WandererKills/1.0"},
      {"Accept", "application/json"}
    ]
  end
end
