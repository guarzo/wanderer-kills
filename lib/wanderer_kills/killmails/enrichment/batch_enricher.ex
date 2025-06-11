defmodule WandererKills.Killmails.Enrichment.BatchEnricher do
  @moduledoc """
  Batch enrichment for killmails to avoid duplicate ESI calls.

  This module collects all unique entity IDs from killmails,
  fetches them in batch, and then applies the enrichment data.
  This avoids making multiple ESI calls for the same entity.
  """

  require Logger
  alias WandererKills.ESI.DataFetcher
  alias WandererKills.ShipTypes.Info, as: ShipInfo
  alias WandererKills.Cache.Helper
  alias WandererKills.Killmails.Transformations

  @type entity_id :: integer()
  @type entity_data :: map()
  @type entity_cache :: %{
          characters: %{entity_id() => entity_data()},
          corporations: %{entity_id() => entity_data()},
          alliances: %{entity_id() => entity_data()},
          ships: %{entity_id() => entity_data()}
        }

  @doc """
  Enriches multiple killmails in batch, avoiding duplicate ESI calls.

  ## Parameters
  - `killmails` - List of killmails to enrich

  ## Returns
  - `{:ok, enriched_killmails}` - List of enriched killmails
  """
  @spec enrich_killmails_batch([map()]) :: {:ok, [map()]}
  def enrich_killmails_batch(killmails) when is_list(killmails) do
    # Step 1: Collect all unique entity IDs
    entity_ids = collect_entity_ids(killmails)

    # Step 2: Fetch all entities in batch
    entity_cache = fetch_entities_batch(entity_ids)

    # Step 3: Apply enrichment using the cache
    enriched = Enum.map(killmails, &enrich_killmail_with_cache(&1, entity_cache))

    {:ok, enriched}
  end

  @doc """
  Enriches a single killmail using a pre-fetched entity cache.

  This is useful when processing killmails in a stream where
  you want to maintain a cache across multiple killmails.
  """
  @spec enrich_killmail_with_cache(map(), entity_cache()) :: map()
  def enrich_killmail_with_cache(killmail, entity_cache) do
    killmail
    |> enrich_victim(entity_cache)
    |> enrich_attackers(entity_cache)
    |> flatten_enriched_data()
  end

  # Private functions

  defp collect_entity_ids(killmails) do
    Enum.reduce(
      killmails,
      %{
        characters: MapSet.new(),
        corporations: MapSet.new(),
        alliances: MapSet.new(),
        ships: MapSet.new()
      },
      fn killmail, acc ->
        acc
        |> collect_victim_ids(killmail["victim"])
        |> collect_attacker_ids(killmail["attackers"] || [])
      end
    )
    |> Enum.map(fn {type, set} -> {type, MapSet.to_list(set)} end)
    |> Map.new()
  end

  defp collect_victim_ids(acc, nil), do: acc

  defp collect_victim_ids(acc, victim) do
    acc
    |> add_id(:characters, victim["character_id"])
    |> add_id(:corporations, victim["corporation_id"])
    |> add_id(:alliances, victim["alliance_id"])
    |> add_id(:ships, victim["ship_type_id"])
  end

  defp collect_attacker_ids(acc, attackers) do
    Enum.reduce(attackers, acc, fn attacker, acc ->
      acc
      |> add_id(:characters, attacker["character_id"])
      |> add_id(:corporations, attacker["corporation_id"])
      |> add_id(:alliances, attacker["alliance_id"])
      |> add_id(:ships, attacker["ship_type_id"])
    end)
  end

  defp add_id(acc, _type, nil), do: acc

  defp add_id(acc, type, id) when is_integer(id) do
    update_in(acc[type], &MapSet.put(&1, id))
  end

  defp fetch_entities_batch(entity_ids) do
    %{
      characters: fetch_batch(:characters, entity_ids[:characters] || []),
      corporations: fetch_batch(:corporations, entity_ids[:corporations] || []),
      alliances: fetch_batch(:alliances, entity_ids[:alliances] || []),
      ships: fetch_batch(:ships, entity_ids[:ships] || [])
    }
  end

  defp fetch_batch(type, ids) when is_list(ids) do
    Logger.debug("Fetching #{length(ids)} #{type} in batch")

    # First check cache for all IDs
    {cached, missing} =
      Enum.split_with(ids, fn id ->
        case get_from_cache(type, id) do
          {:ok, _} -> true
          _ -> false
        end
      end)

    # Get cached data
    cached_data =
      cached
      |> Enum.map(fn id ->
        {:ok, data} = get_from_cache(type, id)
        {id, data}
      end)
      |> Map.new()

    # Fetch missing data concurrently using Flow for better parallelism
    fetched_data =
      if Enum.empty?(missing) do
        %{}
      else
        missing
        |> Flow.from_enumerable(max_demand: 10)
        |> Flow.map(fn id -> {id, fetch_entity(type, id)} end)
        |> Flow.filter(fn {_id, result} -> match?({:ok, _}, result) end)
        |> Flow.map(fn {id, {:ok, data}} -> {id, data} end)
        |> Enum.into(%{})
      end

    Map.merge(cached_data, fetched_data)
  end

  defp get_from_cache(:characters, id), do: Helper.get(:characters, id)
  defp get_from_cache(:corporations, id), do: Helper.get(:corporations, id)
  defp get_from_cache(:alliances, id), do: Helper.get(:alliances, id)
  defp get_from_cache(:ships, id), do: Helper.get(:ship_types, id)

  defp fetch_entity(:characters, id) do
    case DataFetcher.get_character(id) do
      {:ok, data} ->
        Helper.put(:characters, id, data)
        {:ok, data}

      error ->
        error
    end
  end

  defp fetch_entity(:corporations, id) do
    case DataFetcher.get_corporation(id) do
      {:ok, data} ->
        Helper.put(:corporations, id, data)
        {:ok, data}

      error ->
        error
    end
  end

  defp fetch_entity(:alliances, id) do
    case DataFetcher.get_alliance(id) do
      {:ok, data} ->
        Helper.put(:alliances, id, data)
        {:ok, data}

      error ->
        error
    end
  end

  defp fetch_entity(:ships, id) do
    case ShipInfo.get_ship_type(id) do
      {:ok, data} ->
        Helper.put(:ship_types, id, data)
        {:ok, data}

      error ->
        error
    end
  end

  defp enrich_victim(killmail, entity_cache) do
    victim = killmail["victim"] || %{}

    enriched_victim =
      victim
      |> add_entity_data(:character, victim["character_id"], entity_cache.characters)
      |> add_entity_data(:corporation, victim["corporation_id"], entity_cache.corporations)
      |> add_entity_data(:alliance, victim["alliance_id"], entity_cache.alliances)
      |> add_entity_data(:ship, victim["ship_type_id"], entity_cache.ships)

    Map.put(killmail, "victim", enriched_victim)
  end

  defp enrich_attackers(killmail, entity_cache) do
    attackers = killmail["attackers"] || []

    enriched_attackers =
      Enum.map(attackers, fn attacker ->
        attacker
        |> add_entity_data(:character, attacker["character_id"], entity_cache.characters)
        |> add_entity_data(:corporation, attacker["corporation_id"], entity_cache.corporations)
        |> add_entity_data(:alliance, attacker["alliance_id"], entity_cache.alliances)
        |> add_entity_data(:ship, attacker["ship_type_id"], entity_cache.ships)
      end)

    Map.put(killmail, "attackers", enriched_attackers)
  end

  defp add_entity_data(entity, _type, nil, _cache), do: entity

  defp add_entity_data(entity, type, id, cache) do
    case Map.get(cache, id) do
      nil -> entity
      data -> Map.put(entity, to_string(type), data)
    end
  end

  defp flatten_enriched_data(killmail) do
    killmail
    |> Transformations.flatten_enriched_data()
    |> Transformations.add_attacker_count()
    |> Transformations.enrich_with_ship_names()
    |> case do
      {:ok, enriched} -> enriched
    end
  end
end
