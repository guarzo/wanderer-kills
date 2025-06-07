defmodule WandererKills.Cache.Helper do
  @moduledoc """
  Helper module for namespaced cache access using a single Cachex instance.

  Instead of multiple cache instances, this uses a single Cachex instance
  with namespaced keys and appropriate TTLs per namespace.
  """

  alias WandererKills.Core.Config

  @cache_name :wanderer_cache

  # Cache namespaces and their corresponding config keys for TTL
  @namespaces %{
    "esi" => :esi,
    "ship_types" => :esi,
    "systems" => :system,
    "characters" => :esi,
    "corporations" => :esi,
    "alliances" => :esi,
    "killmails" => :killmails
  }

  @doc """
  Get a value from the cache using a namespaced key.

  ## Examples
      iex> WandererKills.Cache.Helper.get("characters", "12345")
      {:ok, character_data}

      iex> WandererKills.Cache.Helper.get("systems", "30000142")
      {:ok, system_data}
  """
  def get(namespace, key) do
    namespaced_key = build_key(namespace, key)
    Cachex.get(@cache_name, namespaced_key)
  end

  @doc """
  Put a value in the cache using a namespaced key with appropriate TTL.

  ## Examples
      iex> WandererKills.Cache.Helper.put("characters", "12345", character_data)
      {:ok, true}
  """
  def put(namespace, key, value) do
    namespaced_key = build_key(namespace, key)
    ttl_ms = get_ttl_for_namespace(namespace)
    Cachex.put(@cache_name, namespaced_key, value, ttl: ttl_ms)
  end

  @doc """
  Delete a value from the cache using a namespaced key.
  """
  def delete(namespace, key) do
    namespaced_key = build_key(namespace, key)
    Cachex.del(@cache_name, namespaced_key)
  end

  @doc """
  Check if a key exists in the cache.
  """
  def exists?(namespace, key) do
    namespaced_key = build_key(namespace, key)

    case Cachex.exists?(@cache_name, namespaced_key) do
      {:ok, exists} -> exists
      _ -> false
    end
  end

  @doc """
  Get or set a value using a fallback function if the key doesn't exist.

  Similar to Cachex.fetch but with namespaced keys.
  """
  def fetch(namespace, key, fallback_fn) do
    namespaced_key = build_key(namespace, key)
    Cachex.fetch(@cache_name, namespaced_key, fallback_fn)
  end

  @doc """
  Get cache statistics for monitoring.
  """
  def stats do
    Cachex.stats(@cache_name)
  end

  @doc """
  Stream entries for a specific namespace pattern.
  """
  def stream(namespace, pattern) do
    namespaced_pattern = build_key(namespace, pattern)

    case Cachex.stream(@cache_name, namespaced_pattern) do
      {:ok, stream} -> {:ok, stream}
      stream when is_struct(stream, Stream) -> {:ok, stream}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_result, other}}
    end
  end

  @doc """
  Clear all entries for a specific namespace.
  """
  def clear_namespace(namespace) do
    pattern = build_key(namespace, "*")

    case Cachex.stream(@cache_name, pattern) do
      {:ok, stream} ->
        stream
        |> Stream.each(fn {key, _value} -> Cachex.del(@cache_name, key) end)
        |> Stream.run()

      stream when is_struct(stream, Stream) ->
        stream
        |> Stream.each(fn {key, _value} -> Cachex.del(@cache_name, key) end)
        |> Stream.run()

      {:error, reason} ->
        raise "Failed to stream cache for clearing: #{inspect(reason)}"
    end
  end

  # Private functions

  defp build_key(namespace, key) do
    "#{namespace}:#{key}"
  end

  defp get_ttl_for_namespace(namespace) do
    cache_config = Config.cache()

    case Map.get(@namespaces, namespace, :esi) do
      :esi -> cache_config.esi_ttl * 1_000
      :system -> cache_config.system_ttl * 1_000
      :killmails -> cache_config.killmails_ttl * 1_000
      _ -> cache_config.esi_ttl * 1_000
    end
  end
end
