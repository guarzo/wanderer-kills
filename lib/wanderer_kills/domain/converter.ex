defmodule WandererKills.Domain.Converter do
  @moduledoc """
  Converts between domain structs and maps for backward compatibility.

  This module provides functions to convert killmail data between the new
  domain structs and the legacy map format used throughout the codebase.
  """

  alias WandererKills.Domain.{Killmail, Victim, Attacker, ZkbMetadata}

  @doc """
  Converts a map-based killmail to a domain struct.

  ## Parameters
    - `killmail_map` - Legacy killmail data as a map

  ## Returns
    - `{:ok, %Killmail{}}` - Successfully converted killmail
    - `{:error, reason}` - Conversion failed

  ## Examples

      iex> Converter.map_to_killmail(%{"killmail_id" => 123, ...})
      {:ok, %Killmail{...}}
  """
  @spec map_to_killmail(map()) :: {:ok, Killmail.t()} | {:error, term()}
  def map_to_killmail(killmail_map) when is_map(killmail_map) do
    Killmail.new(killmail_map)
  end

  @doc """
  Converts a domain struct killmail to a map.

  ## Parameters
    - `killmail` - Killmail struct

  ## Returns
    Map representation of the killmail

  ## Examples

      iex> Converter.killmail_to_map(%Killmail{...})
      %{"killmail_id" => 123, ...}
  """
  @spec killmail_to_map(Killmail.t()) :: map()
  def killmail_to_map(%Killmail{} = killmail) do
    Killmail.to_map(killmail)
  end

  @doc """
  Converts a list of map-based killmails to domain structs.

  ## Parameters
    - `killmail_maps` - List of legacy killmail maps

  ## Returns
    - `{:ok, [%Killmail{}, ...]}` - All killmails converted successfully
    - `{:error, failed_conversions}` - Some conversions failed

  ## Examples

      iex> Converter.maps_to_killmails([%{"killmail_id" => 123}, ...])
      {:ok, [%Killmail{}, ...]}
  """
  @spec maps_to_killmails([map()]) :: {:ok, [Killmail.t()]} | {:error, term()}
  def maps_to_killmails(killmail_maps) when is_list(killmail_maps) do
    results = Enum.map(killmail_maps, &map_to_killmail/1)

    failed =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(failed) do
      killmails = Enum.map(results, fn {:ok, km} -> km end)
      {:ok, killmails}
    else
      {:error, {:partial_conversion, failed}}
    end
  end

  @doc """
  Converts domain structs to maps for JSON serialization.

  ## Parameters
    - `killmails` - List of Killmail structs

  ## Returns
    List of map representations
  """
  @spec killmails_to_maps([Killmail.t()]) :: [map()]
  def killmails_to_maps(killmails) when is_list(killmails) do
    Enum.map(killmails, &killmail_to_map/1)
  end

  @doc """
  Safely converts a map to a killmail struct, returning the original on failure.

  This is useful during migration when you want to gradually adopt structs
  without breaking existing code.

  ## Parameters
    - `data` - Either a map or already a Killmail struct

  ## Returns
    Either a Killmail struct or the original map
  """
  @spec safe_convert(map() | Killmail.t()) :: Killmail.t() | map()
  def safe_convert(%Killmail{} = killmail), do: killmail

  def safe_convert(map) when is_map(map) do
    case map_to_killmail(map) do
      {:ok, killmail} -> killmail
      {:error, _} -> map
    end
  end

  @doc """
  Extracts a specific field from either a struct or map killmail.

  This helper allows code to work with both formats during migration.

  ## Parameters
    - `killmail` - Either a Killmail struct or map
    - `field` - Field name as atom

  ## Returns
    Field value or nil

  ## Examples

      iex> Converter.get_field(killmail, :killmail_id)
      123456789
  """
  @spec get_field(Killmail.t() | map(), atom()) :: term()
  def get_field(%Killmail{} = killmail, field) when is_atom(field) do
    Map.get(killmail, field)
  end

  def get_field(map, field) when is_map(map) and is_atom(field) do
    # Try both string and atom keys
    Map.get(map, to_string(field)) || Map.get(map, field)
  end

  @doc """
  Checks if data is already using domain structs.

  ## Parameters
    - `data` - Data to check

  ## Returns
    Boolean indicating if data uses domain structs
  """
  @spec using_structs?(term()) :: boolean()
  def using_structs?(%Killmail{}), do: true
  def using_structs?(%Victim{}), do: true
  def using_structs?(%Attacker{}), do: true
  def using_structs?(%ZkbMetadata{}), do: true
  def using_structs?(_), do: false

  @doc """
  Updates a killmail (struct or map) with enriched data.

  ## Parameters
    - `killmail` - Original killmail (struct or map)
    - `enriched_data` - Enriched data map

  ## Returns
    Updated killmail in the same format as input
  """
  @spec update_with_enriched_data(Killmail.t() | map(), map()) :: Killmail.t() | map()
  def update_with_enriched_data(%Killmail{} = killmail, enriched_data) do
    Killmail.update_with_enriched_data(killmail, enriched_data)
  end

  def update_with_enriched_data(killmail_map, enriched_data) when is_map(killmail_map) do
    # For maps, merge the enriched data
    Map.merge(killmail_map, enriched_data)
  end
end
