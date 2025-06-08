defmodule WandererKills.Cache.Helper do
  @moduledoc """
  Helper module for namespaced cache access using a single Cachex instance.

  Instead of multiple cache instances, this uses a single Cachex instance
  with namespaced keys and appropriate TTLs per namespace.
  """

  require Logger
  alias WandererKills.Config
  use WandererKills.Cache.EntityHelper

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

  # Define entity-specific cache operations
  define_entity_cache("characters", :character)
  define_entity_cache("corporations", :corporation)
  define_entity_cache("alliances", :alliance)
  define_entity_cache("ship_types", :ship_type)
  define_entity_cache("systems", :system)

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
  Get a value with error handling for domain-specific use.

  Returns {:error, :not_found} if the key doesn't exist instead of {:ok, nil}.
  """
  def get_with_error(namespace, key) do
    case get(namespace, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get or set using a fallback function with proper error handling.

  This wraps the fallback function to handle exceptions and provides
  consistent return values.
  """
  def get_or_set(namespace, key, fallback_fn) do
    case fetch(namespace, key, fn _key ->
           try do
             {:commit, fallback_fn.()}
           rescue
             error ->
               {:ignore, error}
           end
         end) do
      {:ok, value} -> {:ok, value}
      {:commit, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
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
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Clear all entries for a specific namespace.
  """
  def clear_namespace(namespace) do
    pattern = build_key(namespace, "*")

    try do
      case Cachex.stream(@cache_name, pattern) do
        {:ok, stream} ->
          stream
          |> Stream.each(fn {key, _value} -> Cachex.del(@cache_name, key) end)
          |> Stream.run()

          :ok

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, error}
    end
  end

  @doc """
  System-specific complex cache operations.
  """
  def system_get_killmails(system_id) do
    case get("systems", "killmails:#{system_id}") do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, killmail_ids} when is_list(killmail_ids) ->
        {:ok, killmail_ids}

      {:ok, _invalid_data} ->
        # Clean up corrupted data
        delete("systems", "killmails:#{system_id}")
        {:error, :invalid_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def system_put_killmails(system_id, killmail_ids) when is_list(killmail_ids) do
    put("systems", "killmails:#{system_id}", killmail_ids)
  end

  def system_add_killmail(system_id, killmail_id) do
    case system_get_killmails(system_id) do
      {:ok, existing_ids} ->
        if killmail_id in existing_ids do
          {:ok, true}
        else
          new_ids = [killmail_id | existing_ids]
          system_put_killmails(system_id, new_ids)
        end

      {:error, :not_found} ->
        system_put_killmails(system_id, [killmail_id])

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_key(namespace, key) do
    "#{namespace}:#{key}"
  end

  defp get_ttl_for_namespace(namespace) do
    case @namespaces[namespace] do
      nil -> 0
      config_key -> Config.cache()[:"#{config_key}_ttl"] * 1000
    end
  end
end
