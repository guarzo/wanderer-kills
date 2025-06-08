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

  # Define system-specific cache operations using the new macros
  # Note: system_add_killmail is manually defined below for better concurrency
  define_system_cache(:kill_count, count_type: true, default_value: 0)
  define_system_cache(:last_fetch, timestamp_type: true)

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
  Gets killmails for a system.
  """
  def system_get_killmails(system_id) do
    case get("systems", "killmails:#{system_id}") do
      {:ok, nil} -> {:ok, []}
      {:ok, killmails} when is_list(killmails) -> {:ok, killmails}
      {:ok, _invalid} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Puts killmails for a system.
  """
  def system_put_killmails(system_id, killmails) when is_list(killmails) do
    put("systems", "killmails:#{system_id}", killmails)
  end

  @doc """
  Gets cached killmails for a system (enriched killmail data).
  """
  def system_get_cached_killmails(system_id) do
    case get("systems", "cached_killmails:#{system_id}") do
      {:ok, nil} -> {:ok, []}
      {:ok, killmails} when is_list(killmails) -> {:ok, killmails}
      {:ok, _invalid} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Puts cached killmails for a system (enriched killmail data).
  """
  def system_put_cached_killmails(system_id, killmails) when is_list(killmails) do
    put("systems", "cached_killmails:#{system_id}", killmails)
  end

  @doc """
  Alias for system_last_fetch_recent?/1 for backward compatibility - returns boolean directly.
  """
  def system_recently_fetched?(system_id) do
    case system_last_fetch_recent?(system_id) do
      {:ok, result} -> result
    end
  end

  @doc """
  Alias for system_last_fetch_recent?/2 for backward compatibility - returns {:ok, boolean}.
  """
  def system_recently_fetched?(system_id, within_seconds) do
    system_last_fetch_recent?(system_id, within_seconds)
  end

  @doc """
  Alias for system_mark_last_fetch/1 for backward compatibility.
  """
  def system_set_fetch_timestamp(system_id, timestamp) do
    # Convert DateTime to integer seconds if needed
    timestamp_seconds =
      case timestamp do
        %DateTime{} -> DateTime.to_unix(timestamp)
        unix_seconds when is_integer(unix_seconds) -> unix_seconds
        # fallback to current time
        _ -> System.system_time(:second)
      end

    case put("systems", "last_fetch:#{system_id}", timestamp_seconds) do
      {:ok, true} -> {:ok, :set}
      error -> error
    end
  end

  @doc """
  Alias for system_get_last_fetch/1 for backward compatibility.
  Returns error when timestamp doesn't exist (unlike the macro version).
  """
  def system_get_fetch_timestamp(system_id) do
    case get("systems", "last_fetch:#{system_id}") do
      {:ok, nil} -> {:error, :not_found}
      {:ok, timestamp} when is_integer(timestamp) -> {:ok, timestamp}
      {:ok, _invalid} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks if a system is active.
  """
  def system_is_active?(system_id) do
    case get("systems", "active:#{system_id}") do
      {:ok, nil} -> {:ok, false}
      {:ok, _timestamp} -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Adds a killmail to a system's killmail list.

  Uses read-modify-write pattern for consistency with existing test expectations.
  """
  def system_add_killmail(system_id, killmail_id) do
    case system_get_killmails(system_id) do
      {:ok, existing_killmails} ->
        if killmail_id in existing_killmails do
          {:ok, true}
        else
          new_killmails = [killmail_id | existing_killmails]
          system_put_killmails(system_id, new_killmails)
        end

      {:error, :not_found} ->
        # No killmails exist yet, create new list
        system_put_killmails(system_id, [killmail_id])

      {:error, reason} ->
        {:error, reason}
    end
  end

  # System-specific functions that use the macro-generated cache operations

  @doc """
  Adds a system to the active systems list.
  """
  def system_add_active(system_id) do
    timestamp = System.system_time(:second)
    put("systems", "active:#{system_id}", timestamp)
  end

  @doc """
  Gets all active systems.
  """
  def system_get_active_systems do
    try do
      # Use Cachex.keys to get all keys, then filter for active systems
      case Cachex.keys(@cache_name) do
        {:ok, keys} ->
          system_ids =
            keys
            |> Enum.filter(fn key ->
              # Filter for keys that match "systems:active:*" pattern
              String.starts_with?(key, "systems:active:")
            end)
            |> Enum.map(&extract_system_id_from_active_key/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.sort()

          {:ok, system_ids}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, error}
    end
  end

  # Helper function to extract system ID from cache key
  defp extract_system_id_from_active_key(key) do
    # Extract system_id from "systems:active:12345" format
    case String.split(key, ":") do
      ["systems", "active", system_id_str] ->
        case Integer.parse(system_id_str) do
          {system_id, ""} -> system_id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Gets killmail by ID from cache.
  """
  def killmail_get(killmail_id) do
    case get("killmails", "data:#{killmail_id}") do
      {:ok, nil} -> {:error, :not_found}
      {:ok, data} -> {:ok, data}
      error -> error
    end
  end

  @doc """
  Puts killmail data in cache.
  """
  def killmail_put(killmail_id, killmail_data) do
    put("killmails", "data:#{killmail_id}", killmail_data)
  end

  @doc """
  Gets or sets a killmail using a fallback function.
  """
  def killmail_get_or_set(killmail_id, fallback_fn) do
    get_or_set("killmails", "data:#{killmail_id}", fallback_fn)
  end

  @doc """
  Deletes a killmail from cache.
  """
  def killmail_delete(killmail_id) do
    delete("killmails", "data:#{killmail_id}")
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
