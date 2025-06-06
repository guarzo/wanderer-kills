defmodule WandererKills.Killmails.Enricher do
  @moduledoc """
  Enrichment functionality for parsed killmail data.

  This module provides a focused API for enriching killmail data with additional
  information from ESI and other sources. It follows the consistent "Killmail"
  naming convention and minimizes the public API surface.

  ## Features

  - Character/corporation/alliance information enrichment
  - Ship type information enrichment
  - Location and system information enrichment
  - Batch enrichment operations
  - Error handling and graceful degradation

  ## Usage

  ```elixir
  # Enrich a single killmail
  {:ok, enriched} = KillmailEnricher.enrich_killmail(killmail)

  # Enrich with specific options
  {:ok, enriched} = KillmailEnricher.enrich_killmail(killmail, [:characters, :ship_types])
  ```
  """

  require Logger
  alias WandererKills.Cache.Specialized.EsiCache

  @type killmail :: map()
  @type enrichment_option :: :characters | :corporations | :alliances | :ship_types | :locations
  @type enrichment_options :: [enrichment_option()]

  @default_enrichment_options [:characters, :corporations, :alliances, :ship_types]

  @doc """
  Enriches a killmail with additional information from ESI.

  This is the main entry point for killmail enrichment. It fetches additional
  data about characters, corporations, alliances, ships, and locations involved
  in the killmail.

  ## Parameters
  - `killmail` - The killmail data to enrich
  - `options` - List of enrichment options (optional, defaults to standard set)

  ## Returns
  - `{:ok, enriched_killmail}` - On successful enrichment
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  # Basic enrichment with defaults
  {:ok, enriched} = KillmailEnricher.enrich_killmail(killmail)

  # Enrichment with specific options
  {:ok, enriched} = KillmailEnricher.enrich_killmail(killmail, [:characters, :ship_types])

  # Handle enrichment failure gracefully
  case KillmailEnricher.enrich_killmail(killmail) do
    {:ok, enriched} -> process_enriched_killmail(enriched)
    {:error, _reason} -> Logger.warning("Enrichment failed")
  end
  ```
  """
  @spec enrich_killmail(killmail(), enrichment_options()) :: {:ok, killmail()} | {:error, term()}
  def enrich_killmail(killmail, options \\ @default_enrichment_options)

  def enrich_killmail(%{"killmail_id" => killmail_id} = killmail, options)
      when is_integer(killmail_id) and is_list(options) do
    Logger.debug("Starting killmail enrichment",
      killmail_id: killmail_id,
      options: options
    )

    try do
      enriched =
        killmail
        |> enrich_victim_data(options)
        |> enrich_attackers_data(options)
        |> enrich_location_data(options)

      Logger.debug("Completed killmail enrichment", killmail_id: killmail_id)
      {:ok, enriched}
    rescue
      error ->
        Logger.error("Exception during killmail enrichment",
          killmail_id: killmail_id,
          error: inspect(error)
        )

        {:error, :enrichment_exception}
    end
  end

  def enrich_killmail(_, _), do: {:error, :invalid_killmail_format}

  @doc """
  Enriches character information in killmail data.

  ## Parameters
  - `character_id` - The character ID to enrich
  - `base_data` - Existing character data map

  ## Returns
  - Map with enriched character information
  """
  @spec enrich_character_data(integer(), map()) :: map()
  def enrich_character_data(character_id, base_data \\ %{}) when is_integer(character_id) do
    case EsiCache.get_character_info(character_id) do
      {:ok, character_info} ->
        Logger.debug("Enriched character data", character_id: character_id)

        Map.merge(base_data, %{
          "character_name" => character_info["name"],
          "character_info" => character_info
        })

      {:error, reason} ->
        Logger.debug("Failed to enrich character data",
          character_id: character_id,
          error: reason
        )

        base_data
    end
  end

  @doc """
  Enriches corporation information in killmail data.

  ## Parameters
  - `corporation_id` - The corporation ID to enrich
  - `base_data` - Existing corporation data map

  ## Returns
  - Map with enriched corporation information
  """
  @spec enrich_corporation_data(integer(), map()) :: map()
  def enrich_corporation_data(corporation_id, base_data \\ %{}) when is_integer(corporation_id) do
    case EsiCache.get_corporation_info(corporation_id) do
      {:ok, corp_info} ->
        Logger.debug("Enriched corporation data", corporation_id: corporation_id)

        Map.merge(base_data, %{
          "corporation_name" => corp_info["name"],
          "corporation_info" => corp_info
        })

      {:error, reason} ->
        Logger.debug("Failed to enrich corporation data",
          corporation_id: corporation_id,
          error: reason
        )

        base_data
    end
  end

  @doc """
  Enriches alliance information in killmail data.

  ## Parameters
  - `alliance_id` - The alliance ID to enrich (optional)
  - `base_data` - Existing alliance data map

  ## Returns
  - Map with enriched alliance information
  """
  @spec enrich_alliance_data(integer() | nil, map()) :: map()
  def enrich_alliance_data(nil, base_data), do: base_data

  def enrich_alliance_data(alliance_id, base_data) when is_integer(alliance_id) do
    case EsiCache.get_alliance_info(alliance_id) do
      {:ok, alliance_info} ->
        Logger.debug("Enriched alliance data", alliance_id: alliance_id)

        Map.merge(base_data, %{
          "alliance_name" => alliance_info["name"],
          "alliance_info" => alliance_info
        })

      {:error, reason} ->
        Logger.debug("Failed to enrich alliance data",
          alliance_id: alliance_id,
          error: reason
        )

        base_data
    end
  end

  @doc """
  Enriches ship type information in killmail data.

  ## Parameters
  - `ship_type_id` - The ship type ID to enrich
  - `base_data` - Existing ship data map

  ## Returns
  - Map with enriched ship type information
  """
  @spec enrich_ship_type_data(integer(), map()) :: map()
  def enrich_ship_type_data(ship_type_id, base_data \\ %{}) when is_integer(ship_type_id) do
    case EsiCache.get_type_info(ship_type_id) do
      {:ok, type_info} ->
        Logger.debug("Enriched ship type data", ship_type_id: ship_type_id)

        Map.merge(base_data, %{
          "ship_type_name" => type_info["name"],
          "ship_type_info" => type_info
        })

      {:error, reason} ->
        Logger.debug("Failed to enrich ship type data",
          ship_type_id: ship_type_id,
          error: reason
        )

        base_data
    end
  end

  # Private enrichment functions

  @spec enrich_victim_data(killmail(), enrichment_options()) :: killmail()
  defp enrich_victim_data(%{"victim" => victim} = killmail, options) do
    enriched_victim =
      victim
      |> maybe_enrich_character(:characters, victim["character_id"], options)
      |> maybe_enrich_corporation(:corporations, victim["corporation_id"], options)
      |> maybe_enrich_alliance(:alliances, victim["alliance_id"], options)
      |> maybe_enrich_ship_type(:ship_types, victim["ship_type_id"], options)

    Map.put(killmail, "victim", enriched_victim)
  end

  defp enrich_victim_data(killmail, _), do: killmail

  @spec enrich_attackers_data(killmail(), enrichment_options()) :: killmail()
  defp enrich_attackers_data(%{"attackers" => attackers} = killmail, options)
       when is_list(attackers) do
    enriched_attackers =
      Enum.map(attackers, fn attacker ->
        attacker
        |> maybe_enrich_character(:characters, attacker["character_id"], options)
        |> maybe_enrich_corporation(:corporations, attacker["corporation_id"], options)
        |> maybe_enrich_alliance(:alliances, attacker["alliance_id"], options)
        |> maybe_enrich_ship_type(:ship_types, attacker["ship_type_id"], options)
      end)

    Map.put(killmail, "attackers", enriched_attackers)
  end

  defp enrich_attackers_data(killmail, _), do: killmail

  @spec enrich_location_data(killmail(), enrichment_options()) :: killmail()
  defp enrich_location_data(%{"solar_system_id" => system_id} = killmail, options)
       when is_integer(system_id) do
    if :locations in options do
      case EsiCache.get_system_info(system_id) do
        {:ok, system_info} ->
          Logger.debug("Enriched location data", solar_system_id: system_id)

          Map.merge(killmail, %{
            "solar_system_name" => system_info["name"],
            "solar_system_info" => system_info
          })

        {:error, reason} ->
          Logger.debug("Failed to enrich location data",
            solar_system_id: system_id,
            error: reason
          )

          killmail
      end
    else
      killmail
    end
  end

  defp enrich_location_data(killmail, _), do: killmail

  # Helper functions for conditional enrichment

  @spec maybe_enrich_character(map(), enrichment_option(), integer() | nil, enrichment_options()) ::
          map()
  defp maybe_enrich_character(data, :characters, character_id, options)
       when is_integer(character_id) do
    if :characters in options do
      enrich_character_data(character_id, data)
    else
      data
    end
  end

  defp maybe_enrich_character(data, _, _, _), do: data

  @spec maybe_enrich_corporation(
          map(),
          enrichment_option(),
          integer() | nil,
          enrichment_options()
        ) :: map()
  defp maybe_enrich_corporation(data, :corporations, corp_id, options)
       when is_integer(corp_id) do
    if :corporations in options do
      enrich_corporation_data(corp_id, data)
    else
      data
    end
  end

  defp maybe_enrich_corporation(data, _, _, _), do: data

  @spec maybe_enrich_alliance(map(), enrichment_option(), integer() | nil, enrichment_options()) ::
          map()
  defp maybe_enrich_alliance(data, :alliances, alliance_id, options)
       when is_integer(alliance_id) do
    if :alliances in options do
      enrich_alliance_data(alliance_id, data)
    else
      data
    end
  end

  defp maybe_enrich_alliance(data, _, _, _), do: data

  @spec maybe_enrich_ship_type(map(), enrichment_option(), integer() | nil, enrichment_options()) ::
          map()
  defp maybe_enrich_ship_type(data, :ship_types, ship_type_id, options)
       when is_integer(ship_type_id) do
    if :ship_types in options do
      enrich_ship_type_data(ship_type_id, data)
    else
      data
    end
  end

  defp maybe_enrich_ship_type(data, _, _, _), do: data
end
