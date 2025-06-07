defmodule WandererKills.ESI.CharacterFetcher do
  @moduledoc """
  ESI Character data fetcher.

  This module handles fetching character information from the EVE ESI API,
  including character details, corporation info, and alliance info.
  """

  require Logger
  alias WandererKills.Core.{Config, Error}
  alias WandererKills.Core.Behaviours.{ESIClient, DataFetcher}
  alias WandererKills.Cache.ESI

  @behaviour ESIClient
  @behaviour DataFetcher

  @doc """
  Fetches character information from ESI and caches it.
  """
  @impl ESIClient
  def get_character(character_id) when is_integer(character_id) do
    ESI.get_or_set_character(character_id, fn ->
      fetch_character_from_api(character_id)
    end)
  end

  @impl ESIClient
  def get_character_batch(character_ids) when is_list(character_ids) do
    Enum.map(character_ids, &get_character/1)
  end

  @doc """
  Fetches corporation information from ESI and caches it.
  """
  @impl ESIClient
  def get_corporation(corporation_id) when is_integer(corporation_id) do
    ESI.get_or_set_corporation(corporation_id, fn ->
      fetch_corporation_from_api(corporation_id)
    end)
  end

  @impl ESIClient
  def get_corporation_batch(corporation_ids) when is_list(corporation_ids) do
    Enum.map(corporation_ids, &get_corporation/1)
  end

  @doc """
  Fetches alliance information from ESI and caches it.
  """
  @impl ESIClient
  def get_alliance(alliance_id) when is_integer(alliance_id) do
    ESI.get_or_set_alliance(alliance_id, fn ->
      fetch_alliance_from_api(alliance_id)
    end)
  end

  @impl ESIClient
  def get_alliance_batch(alliance_ids) when is_list(alliance_ids) do
    Enum.map(alliance_ids, &get_alliance/1)
  end

  # DataFetcher behaviour implementations
  @impl DataFetcher
  def fetch({:character, character_id}), do: get_character(character_id)
  def fetch({:corporation, corporation_id}), do: get_corporation(corporation_id)
  def fetch({:alliance, alliance_id}), do: get_alliance(alliance_id)
  def fetch(_), do: {:error, Error.esi_error(:unsupported, "Unsupported fetch operation")}

  @impl DataFetcher
  def fetch_many(fetch_args) when is_list(fetch_args) do
    Enum.map(fetch_args, &fetch/1)
  end

  @impl DataFetcher
  def supports?({:character, _}), do: true
  def supports?({:corporation, _}), do: true
  def supports?({:alliance, _}), do: true
  def supports?(_), do: false

  # Not implemented for this module
  @impl ESIClient
  def get_type(_), do: {:error, Error.esi_error(:not_implemented, "Type fetching not supported")}
  @impl ESIClient
  def get_type_batch(type_ids) when is_list(type_ids),
    do:
      Enum.map(type_ids, fn _ ->
        {:error, Error.esi_error(:not_implemented, "Type fetching not supported")}
      end)

  @impl ESIClient
  def get_group(_),
    do: {:error, Error.esi_error(:not_implemented, "Group fetching not supported")}

  @impl ESIClient
  def get_group_batch(group_ids) when is_list(group_ids),
    do:
      Enum.map(group_ids, fn _ ->
        {:error, Error.esi_error(:not_implemented, "Group fetching not supported")}
      end)

  @impl ESIClient
  def get_system(_),
    do: {:error, Error.esi_error(:not_implemented, "System fetching not supported")}

  @impl ESIClient
  def get_system_batch(system_ids) when is_list(system_ids),
    do:
      Enum.map(system_ids, fn _ ->
        {:error, Error.esi_error(:not_implemented, "System fetching not supported")}
      end)

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp fetch_character_from_api(character_id) do
    url = "#{esi_base_url()}/characters/#{character_id}/"

    case http_client().get(url, default_headers(), []) do
      {:ok, response} ->
        parse_character_response(character_id, response)

      {:error, reason} ->
        Logger.error("Failed to fetch character #{character_id}: #{inspect(reason)}")

        raise Error.esi_error(:api_error, "Failed to fetch character from ESI", false, %{
                character_id: character_id,
                reason: reason
              })
    end
  end

  defp fetch_corporation_from_api(corporation_id) do
    url = "#{esi_base_url()}/corporations/#{corporation_id}/"

    case http_client().get(url, default_headers(), []) do
      {:ok, response} ->
        parse_corporation_response(corporation_id, response)

      {:error, reason} ->
        Logger.error("Failed to fetch corporation #{corporation_id}: #{inspect(reason)}")

        raise Error.esi_error(:api_error, "Failed to fetch corporation from ESI", false, %{
                corporation_id: corporation_id,
                reason: reason
              })
    end
  end

  defp fetch_alliance_from_api(alliance_id) do
    url = "#{esi_base_url()}/alliances/#{alliance_id}/"

    case http_client().get(url, default_headers(), []) do
      {:ok, response} ->
        parse_alliance_response(alliance_id, response)

      {:error, reason} ->
        Logger.error("Failed to fetch alliance #{alliance_id}: #{inspect(reason)}")

        raise Error.esi_error(:api_error, "Failed to fetch alliance from ESI", false, %{
                alliance_id: alliance_id,
                reason: reason
              })
    end
  end

  defp parse_character_response(character_id, %{body: body}) do
    %{
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
  end

  defp parse_corporation_response(corporation_id, %{body: body}) do
    %{
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
  end

  defp parse_alliance_response(alliance_id, %{body: body}) do
    %{
      "alliance_id" => alliance_id,
      "name" => Map.get(body, "name"),
      "ticker" => Map.get(body, "ticker"),
      "creator_corporation_id" => Map.get(body, "creator_corporation_id"),
      "creator_id" => Map.get(body, "creator_id"),
      "date_founded" => Map.get(body, "date_founded"),
      "executor_corporation_id" => Map.get(body, "executor_corporation_id"),
      "faction_id" => Map.get(body, "faction_id")
    }
  end

  defp esi_base_url, do: Config.service_url(:esi)
  defp http_client, do: Config.http_client()

  defp default_headers do
    [
      {"User-Agent", "WandererKills/1.0"},
      {"Accept", "application/json"}
    ]
  end
end
