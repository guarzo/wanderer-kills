defmodule WandererKills.ESI.Client do
  @moduledoc """
  ESI (EVE Swagger Interface) API client coordinator.

  This module acts as the main interface for ESI operations, delegating
  to specialized fetcher modules for different types of data.
  """

  require Logger
  alias WandererKills.Core.{Config, Error}
  alias WandererKills.ESI.{CharacterFetcher, TypeFetcher, KillmailFetcher}
  alias WandererKills.Core.Behaviours.ESIClient

  @behaviour ESIClient

  @doc """
  Gets ESI base URL from configuration.
  """
  def base_url, do: Config.service_url(:esi)

  # ============================================================================
  # ESIClient Behaviour Implementation
  # ============================================================================

  @impl ESIClient
  def get_character(character_id), do: CharacterFetcher.get_character(character_id)

  @impl ESIClient
  def get_character_batch(character_ids), do: CharacterFetcher.get_character_batch(character_ids)

  @impl ESIClient
  def get_corporation(corporation_id), do: CharacterFetcher.get_corporation(corporation_id)

  @impl ESIClient
  def get_corporation_batch(corporation_ids),
    do: CharacterFetcher.get_corporation_batch(corporation_ids)

  @impl ESIClient
  def get_alliance(alliance_id), do: CharacterFetcher.get_alliance(alliance_id)

  @impl ESIClient
  def get_alliance_batch(alliance_ids), do: CharacterFetcher.get_alliance_batch(alliance_ids)

  @impl ESIClient
  def get_type(type_id), do: TypeFetcher.get_type(type_id)

  @impl ESIClient
  def get_type_batch(type_ids), do: TypeFetcher.get_type_batch(type_ids)

  @impl ESIClient
  def get_group(group_id), do: TypeFetcher.get_group(group_id)

  @impl ESIClient
  def get_group_batch(group_ids), do: TypeFetcher.get_group_batch(group_ids)

  @impl ESIClient
  def get_system(_system_id) do
    {:error, Error.esi_error(:not_implemented, "System fetching not yet implemented")}
  end

  @impl ESIClient
  def get_system_batch(_system_ids) do
    {:error, Error.esi_error(:not_implemented, "System fetching not yet implemented")}
  end

  # ============================================================================
  # Killmail Operations
  # ============================================================================

  @doc """
  Fetches a killmail from ESI using killmail ID and hash.
  """
  def get_killmail(killmail_id, killmail_hash) do
    KillmailFetcher.get_killmail(killmail_id, killmail_hash)
  end

  @doc """
  Fetches multiple killmails concurrently.
  """
  def get_killmails_batch(killmail_specs) do
    KillmailFetcher.get_killmails_batch(killmail_specs)
  end

  # ============================================================================
  # Ship Type Operations
  # ============================================================================

  @doc """
  Returns the default ship group IDs.
  """
  def ship_group_ids, do: TypeFetcher.ship_group_ids()

  @doc """
  Updates ship groups by fetching fresh data from ESI.
  """
  def update_ship_groups(group_ids \\ nil) do
    group_ids = group_ids || TypeFetcher.ship_group_ids()
    TypeFetcher.update_ship_groups(group_ids)
  end

  @doc """
  Fetches ship types for specific groups.
  """
  def fetch_ship_types_for_groups(group_ids \\ nil) do
    group_ids = group_ids || TypeFetcher.ship_group_ids()
    TypeFetcher.fetch_ship_types_for_groups(group_ids)
  end

  # ============================================================================
  # Legacy Compatibility (Deprecated)
  # ============================================================================

  @doc """
  Legacy function for ensuring data is cached.

  **Deprecated**: Use specific fetcher modules directly.
  """
  def ensure_cached(type, id) do
    Logger.warning("ensure_cached/2 is deprecated, use specific fetcher modules instead",
      type: type,
      id: id
    )

    case type do
      :character -> get_character(id) |> convert_to_ok()
      :corporation -> get_corporation(id) |> convert_to_ok()
      :alliance -> get_alliance(id) |> convert_to_ok()
      :type -> get_type(id) |> convert_to_ok()
      :group -> get_group(id) |> convert_to_ok()
      _ -> {:error, Error.esi_error(:unsupported, "Unsupported ensure_cached type: #{type}")}
    end
  end

  defp convert_to_ok({:ok, _}), do: :ok
  defp convert_to_ok({:error, reason}), do: {:error, reason}

  # ============================================================================
  # Ship Type Source Behaviour (Legacy Compatibility)
  # ============================================================================

  @doc """
  Legacy ship type source name.

  **Deprecated**: Ship type source behaviour is deprecated.
  """
  def source_name, do: "ESI"

  @doc """
  Legacy download function.

  **Deprecated**: Use fetch_ship_types_for_groups/1 instead.
  """
  def download(opts \\ []) do
    Logger.warning("download/1 is deprecated, use fetch_ship_types_for_groups/1 instead")

    group_ids = Keyword.get(opts, :group_ids, TypeFetcher.ship_group_ids())

    case fetch_ship_types_for_groups(group_ids) do
      {:ok, types} -> {:ok, convert_types_to_legacy_format(types)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Legacy parse function.

  **Deprecated**: Parsing is now handled internally by fetcher modules.
  """
  def parse(ship_groups) when is_list(ship_groups) do
    Logger.warning("parse/1 is deprecated, data is now parsed automatically by fetcher modules")
    {:ok, ship_groups}
  end

  @doc """
  Legacy update function.

  **Deprecated**: Use update_ship_groups/1 instead.
  """
  def update(opts \\ []) do
    Logger.warning("update/1 is deprecated, use update_ship_groups/1 instead")

    group_ids = Keyword.get(opts, :group_ids, TypeFetcher.ship_group_ids())
    update_ship_groups(group_ids)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp convert_types_to_legacy_format(types) do
    # Convert new format to legacy format for backwards compatibility
    Enum.map(types, fn type ->
      %{
        "type_id" => Map.get(type, "type_id"),
        "name" => Map.get(type, "name"),
        "group_id" => Map.get(type, "group_id")
      }
    end)
  end
end
