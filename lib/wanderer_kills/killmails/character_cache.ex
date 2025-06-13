defmodule WandererKills.Killmails.CharacterCache do
  @moduledoc """
  Provides caching for extracted character IDs from killmails.

  This module caches the results of character extraction to avoid
  repeated parsing of the same killmail data. Uses Cachex with
  configurable TTL.

  ## Caching Strategy

  - **Cache Key**: `"character_extraction:{killmail_id}"`
  - **TTL**: 5 minutes (configurable via `:character_cache, :ttl_ms`)
  - **Namespace**: `"character_extraction"`
  - **Storage**: Shared Cachex instance (`:wanderer_cache`)

  ## Performance Benefits

  Character extraction can be expensive for killmails with many attackers.
  Caching provides significant performance improvements for:
  - Repeated processing of the same killmails
  - Batch operations on overlapping killmail sets
  - Subscription filtering with character lists

  ## Batch Processing

  The module provides efficient batch processing with:
  - Parallel cache lookups for multiple killmails
  - Concurrent character extraction for cache misses
  - Automatic cache population for extracted data
  - Comprehensive telemetry reporting

  ## Telemetry & Monitoring

  Emits `[:wanderer_kills, :character, :cache]` events for:
  - `:hit` - Successful cache lookups
  - `:miss` - Cache misses requiring extraction
  - `:put` - Cache storage operations

  Also emits batch telemetry for large operations (>50 killmails):
  - Cache effectiveness statistics
  - Hit rate percentages
  - Performance metrics

  ## Configuration

      config :wanderer_kills, :character_cache,
        ttl_ms: :timer.minutes(5)  # 5 minute TTL

  ## Usage Examples

      # Single killmail caching
      characters = CharacterCache.extract_characters_cached(killmail)

      # Batch processing with caching
      killmail_character_map = CharacterCache.batch_extract_cached(killmails)

      # Cache management
      CharacterCache.warm_cache(killmails)
      CharacterCache.clear_cache()
      stats = CharacterCache.get_cache_stats()
  """

  alias WandererKills.Killmails.CharacterMatcher
  alias WandererKills.Config
  alias WandererKills.Observability.Telemetry

  require Logger

  @cache_name :wanderer_cache
  @namespace "character_extraction"
  @default_ttl :timer.minutes(5)

  @doc """
  Extracts character IDs from a killmail, using cache when possible.

  ## Parameters
    - killmail: The killmail map
    
  ## Returns
    - List of character IDs found in the killmail
  """
  @spec extract_characters_cached(map()) :: [integer()]
  def extract_characters_cached(killmail) when is_map(killmail) do
    killmail_id = killmail["killmail_id"]

    case killmail_id do
      nil ->
        # No killmail_id, can't cache
        CharacterMatcher.extract_character_ids(killmail)

      id ->
        cache_key = build_cache_key(id)

        case get_from_cache(cache_key) do
          {:ok, characters} ->
            Telemetry.character_cache(:hit, cache_key, %{killmail_id: id})
            characters

          {:error, _} ->
            Telemetry.character_cache(:miss, cache_key, %{killmail_id: id})

            # Extract and cache
            characters = CharacterMatcher.extract_character_ids(killmail)
            put_in_cache(cache_key, characters)
            characters
        end
    end
  end

  @doc """
  Batch extracts characters from multiple killmails with caching.

  ## Parameters
    - killmails: List of killmail maps
    
  ## Returns
    - Map of killmail_id => [character_ids]
  """
  @spec batch_extract_cached([map()]) :: %{integer() => [integer()]}
  def batch_extract_cached(killmails) when is_list(killmails) do
    # Separate killmails with and without IDs
    {with_ids, without_ids} = Enum.split_with(killmails, & &1["killmail_id"])

    # Process killmails with IDs (cacheable)
    cached_results = process_cacheable_killmails(with_ids)

    # Process killmails without IDs (non-cacheable)
    uncached_results =
      without_ids
      |> Enum.map(fn km ->
        {System.unique_integer(), CharacterMatcher.extract_character_ids(km)}
      end)
      |> Map.new()

    Map.merge(cached_results, uncached_results)
  end

  @doc """
  Warms the cache with character data from multiple killmails.

  Useful for preloading cache after fetching new killmails.
  """
  @spec warm_cache([map()]) :: :ok
  def warm_cache(killmails) when is_list(killmails) do
    killmails
    |> Enum.filter(& &1["killmail_id"])
    |> Enum.each(fn killmail ->
      cache_key = build_cache_key(killmail["killmail_id"])

      if !cached?(cache_key) do
        characters = CharacterMatcher.extract_character_ids(killmail)
        put_in_cache(cache_key, characters)
      end
    end)

    :ok
  end

  @doc """
  Gets cache statistics for character extraction.
  """
  @spec get_cache_stats() :: map()
  def get_cache_stats do
    case Cachex.stats(@cache_name) do
      {:ok, stats} ->
        # Cachex stats structure is different - it's just counts
        hits = Map.get(stats, :hits, 0)
        misses = Map.get(stats, :misses, 0)
        total = hits + misses

        hit_rate = if total > 0, do: hits / total * 100, else: 0.0

        %{
          namespace: @namespace,
          hits: hits,
          misses: misses,
          total_requests: total,
          hit_rate: Float.round(hit_rate, 2),
          ttl_minutes: div(@default_ttl, 60_000)
        }

      {:error, _} ->
        %{
          namespace: @namespace,
          error: "Unable to fetch cache stats"
        }
    end
  end

  @doc """
  Clears all character extraction cache entries.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    # Get all keys and filter by our namespace
    case Cachex.keys(@cache_name) do
      {:ok, keys} ->
        keys
        |> Enum.filter(&String.starts_with?(&1, @namespace <> ":"))
        |> Enum.each(&Cachex.del(@cache_name, &1))

      {:error, _} ->
        Logger.warning("Failed to clear character cache")
    end

    :ok
  end

  # Private functions

  defp build_cache_key(killmail_id) do
    "#{@namespace}:#{killmail_id}"
  end

  defp get_from_cache(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  defp put_in_cache(key, value) do
    ttl = Config.get([:character_cache, :ttl_ms], @default_ttl)
    result = Cachex.put(@cache_name, key, value, ttl: ttl)
    Telemetry.character_cache(:put, key, %{character_count: length(value)})
    result
  end

  defp cached?(key) do
    case Cachex.exists?(@cache_name, key) do
      {:ok, exists} -> exists
      _ -> false
    end
  end

  defp process_cacheable_killmails(killmails) do
    # Build list of cache keys to check
    cache_checks =
      killmails
      |> Enum.map(fn km ->
        {km["killmail_id"], build_cache_key(km["killmail_id"]), km}
      end)

    # Batch check cache
    {cached, uncached} =
      Enum.split_with(cache_checks, fn {_id, key, _km} ->
        cached?(key)
      end)

    # Get cached results
    cached_results =
      cached
      |> Task.async_stream(
        fn {id, key, _km} ->
          case get_from_cache(key) do
            {:ok, chars} -> {id, chars}
            _ -> nil
          end
        end,
        max_concurrency: System.schedulers_online(),
        ordered: false
      )
      |> Enum.reduce(%{}, fn
        {:ok, {id, chars}}, acc when not is_nil(chars) ->
          Map.put(acc, id, chars)

        _, acc ->
          acc
      end)

    # Process uncached killmails
    uncached_results =
      uncached
      |> Task.async_stream(
        fn {id, key, km} ->
          characters = CharacterMatcher.extract_character_ids(km)
          put_in_cache(key, characters)
          {id, characters}
        end,
        max_concurrency: System.schedulers_online(),
        ordered: false
      )
      |> Enum.reduce(%{}, fn
        {:ok, {id, chars}}, acc -> Map.put(acc, id, chars)
        _, acc -> acc
      end)

    # Report telemetry
    hit_count = map_size(cached_results)
    miss_count = map_size(uncached_results)
    total = length(killmails)

    :telemetry.execute(
      [:wanderer_kills, :character_cache, :batch],
      %{
        hits: hit_count,
        misses: miss_count,
        total: total
      },
      %{}
    )

    # Log cache effectiveness for large batches
    if total > 50 do
      hit_rate = if total > 0, do: Float.round(hit_count / total * 100, 1), else: 0.0

      Logger.info("📈 Character cache batch performance",
        total_killmails: total,
        cache_hits: hit_count,
        cache_misses: miss_count,
        hit_rate_percent: hit_rate
      )
    end

    Map.merge(cached_results, uncached_results)
  end
end
