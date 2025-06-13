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

  # Get the configured cache adapter
  defp cache_adapter do
    Application.get_env(:wanderer_kills, :cache_adapter, Cachex)
  end

  # Helper function to get cache stats that works with different adapters
  defp get_cache_stats_internal do
    adapter = cache_adapter()

    case adapter do
      Cachex ->
        Cachex.stats(@cache_name)

      _ ->
        # For ETS adapter and others, we don't have detailed stats
        case adapter.size(@cache_name) do
          {:ok, size} -> {:ok, %{hits: 0, misses: 0, size: size}}
          error -> error
        end
    end
  end

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
    try do
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
    rescue
      _error ->
        # Cache became unavailable during processing, fall back
        fallback_batch_extract(killmails)
    end
  end

  # Fallback function for when cache is not available
  defp fallback_batch_extract(killmails) do
    killmails
    |> Enum.map(fn killmail ->
      id = killmail["killmail_id"] || System.unique_integer()
      characters = CharacterMatcher.extract_character_ids(killmail)
      {id, characters}
    end)
    |> Map.new()
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
    case get_cache_stats_internal() do
      {:ok, stats} ->
        # Cachex stats structure is different - it's just counts
        hits = Map.get(stats, :hits, 0)
        misses = Map.get(stats, :misses, 0)
        total = hits + misses

        hit_rate = if total > 0, do: hits / total * 100, else: 0.0

        # Get the size (number of entries) in the cache
        size =
          case Cachex.size(@cache_name) do
            {:ok, count} -> count
            _ -> 0
          end

        %{
          namespace: @namespace,
          hits: hits,
          misses: misses,
          total_requests: total,
          hit_rate: Float.round(hit_rate, 2),
          ttl_minutes: div(Config.get([:character_cache, :ttl_ms], @default_ttl), 60_000),
          entries: size
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

  This function only clears entries within the character extraction namespace,
  preserving other cached data like ESI data, system data, and ship types.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    adapter = cache_adapter()

    case adapter do
      Cachex -> clear_cachex_namespace()
      _ -> clear_generic_cache(adapter)
    end
  end

  # Clear only character extraction namespace from Cachex
  defp clear_cachex_namespace do
    case Cachex.keys(@cache_name) do
      {:ok, all_keys} ->
        namespace_keys = Enum.filter(all_keys, &String.starts_with?(&1, @namespace <> ":"))

        # Delete only the character extraction keys
        Enum.each(namespace_keys, &Cachex.del(@cache_name, &1))

        Logger.debug("Cleared #{length(namespace_keys)} character cache entries")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to get cache keys for clearing: #{inspect(reason)}")
        :ok
    end
  end

  # Clear entire cache for non-Cachex adapters (primarily for testing)
  defp clear_generic_cache(adapter) do
    case adapter.clear(@cache_name) do
      {:ok, _count} ->
        Logger.debug("Cleared entire cache (using non-Cachex adapter)")
        :ok

      {:error, _} ->
        Logger.warning("Failed to clear character cache")
        :ok
    end
  end

  # Private functions

  defp build_cache_key(killmail_id) do
    "#{@namespace}:#{killmail_id}"
  end

  defp get_from_cache(key) do
    adapter = cache_adapter()

    result =
      case adapter do
        Cachex ->
          # Cachex supports get/3 with options
          Cachex.get(@cache_name, key, [])

        _ ->
          # Other adapters use get/2 from the behavior
          adapter.get(@cache_name, key)
      end

    case result do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      # Propagate genuine errors properly
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_in_cache(key, value) do
    ttl = Config.get([:character_cache, :ttl_ms], @default_ttl)
    result = cache_adapter().put(@cache_name, key, value, ttl: ttl)
    Telemetry.character_cache(:put, key, %{character_count: length(value)})
    result
  end

  defp cached?(key) do
    case cache_adapter().exists?(@cache_name, key) do
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

    # Optimized: Single cache operation per key instead of exists? + get
    {cached_results, uncached} =
      cache_checks
      |> Task.async_stream(
        fn {id, key, km} ->
          case get_from_cache(key) do
            {:ok, chars} -> {:cached, {id, chars}}
            {:error, :not_found} -> {:uncached, {id, key, km}}
            # Treat other errors as cache miss
            _ -> {:uncached, {id, key, km}}
          end
        end,
        max_concurrency: System.schedulers_online(),
        ordered: false
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {:cached, result}}, {cached_acc, uncached_acc} ->
          {[result | cached_acc], uncached_acc}

        {:ok, {:uncached, item}}, {cached_acc, uncached_acc} ->
          {cached_acc, [item | uncached_acc]}

        _, {cached_acc, uncached_acc} ->
          {cached_acc, uncached_acc}
      end)

    # Convert cached results to map
    cached_results_map = Map.new(cached_results)

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
    hit_count = map_size(cached_results_map)
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

    Map.merge(cached_results_map, uncached_results)
  end
end
