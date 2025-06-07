defmodule WandererKills.ESI.Client do
  @moduledoc """
  ESI (EVE Swagger Interface) API client coordinator.

  This module acts as the main interface for ESI operations, delegating
  to specialized fetcher modules for different types of data.
  """

  require Logger
  alias WandererKills.Infrastructure.Config
  alias WandererKills.ESI.DataFetcher
  alias WandererKills.Infrastructure.Behaviours.ESIClient

  @behaviour ESIClient

  @doc """
  Gets ESI base URL from configuration.
  """
  def base_url, do: Config.services().esi_base_url

  # ============================================================================
  # ESIClient Behaviour Implementation
  # ============================================================================

  @impl ESIClient
  def get_character(character_id), do: DataFetcher.get_character(character_id)

  @impl ESIClient
  def get_character_batch(character_ids), do: DataFetcher.get_character_batch(character_ids)

  @impl ESIClient
  def get_corporation(corporation_id), do: DataFetcher.get_corporation(corporation_id)

  @impl ESIClient
  def get_corporation_batch(corporation_ids),
    do: DataFetcher.get_corporation_batch(corporation_ids)

  @impl ESIClient
  def get_alliance(alliance_id), do: DataFetcher.get_alliance(alliance_id)

  @impl ESIClient
  def get_alliance_batch(alliance_ids), do: DataFetcher.get_alliance_batch(alliance_ids)

  @impl ESIClient
  def get_type(type_id), do: DataFetcher.get_type(type_id)

  @impl ESIClient
  def get_type_batch(type_ids), do: DataFetcher.get_type_batch(type_ids)

  @impl ESIClient
  def get_group(group_id), do: DataFetcher.get_group(group_id)

  @impl ESIClient
  def get_group_batch(group_ids), do: DataFetcher.get_group_batch(group_ids)

  @impl ESIClient
  def get_system(system_id), do: DataFetcher.get_system(system_id)

  @impl ESIClient
  def get_system_batch(system_ids), do: DataFetcher.get_system_batch(system_ids)

  # ============================================================================
  # Killmail Operations
  # ============================================================================

  @doc """
  Fetches a killmail from ESI using killmail ID and hash.
  """
  def get_killmail(killmail_id, killmail_hash) do
    DataFetcher.get_killmail(killmail_id, killmail_hash)
  end

  @doc """
  Fetches a killmail directly from ESI API (raw implementation).

  This provides direct access to the ESI API for killmail fetching,
  which is used by the parser when full killmail data is needed.
  """
  @spec get_killmail_raw(integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_killmail_raw(killmail_id, killmail_hash) do
    DataFetcher.get_killmail_raw(killmail_id, killmail_hash)
  end

  @doc """
  Fetches multiple killmails concurrently.
  """
  def get_killmails_batch(killmail_specs) do
    DataFetcher.get_killmails_batch(killmail_specs)
  end

  # ============================================================================
  # Ship Type Operations
  # ============================================================================

  @doc """
  Returns the default ship group IDs.
  """
  def ship_group_ids, do: DataFetcher.ship_group_ids()

  @doc """
  Returns the source name for this ESI client.
  """
  def source_name, do: "ESI"

  @doc """
  General update function that delegates to update_ship_groups.

  This provides compatibility for modules that expect a general update function.

  ## Options
  - `opts` - Keyword list of options
    - `group_ids` - List of group IDs to fetch (optional)

  ## Examples
      iex> ESI.Client.update()
      :ok

      iex> ESI.Client.update(group_ids: [23, 16])
      :ok
  """
  def update(opts \\ []) do
    group_ids = Keyword.get(opts, :group_ids)
    update_ship_groups(group_ids)
  end

  @doc """
  Updates ship groups by fetching fresh data from ESI.
  """
  def update_ship_groups(group_ids \\ nil) do
    group_ids = group_ids || DataFetcher.ship_group_ids()
    DataFetcher.update_ship_groups(group_ids)
  end

  @doc """
  Fetches ship types for specific groups.
  """
  def fetch_ship_types_for_groups(group_ids \\ nil) do
    group_ids = group_ids || DataFetcher.ship_group_ids()
    DataFetcher.fetch_ship_types_for_groups(group_ids)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================
end
