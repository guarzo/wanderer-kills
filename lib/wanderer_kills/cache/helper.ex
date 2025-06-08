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

  @doc """
  Gets the kill count for a system.
  """
  def system_get_kill_count(system_id) do
    case get("systems", "kill_count:#{system_id}") do
      {:ok, nil} -> {:ok, 0}
      {:ok, count} when is_integer(count) -> {:ok, count}
      # Clean up corrupted data
      {:ok, _invalid} -> {:ok, 0}
      {:error, _reason} -> {:ok, 0}
    end
  end

  @doc """
  Sets the kill count for a system.
  """
  def system_put_kill_count(system_id, count) when is_integer(count) do
    put("systems", "kill_count:#{system_id}", count)
  end

  @doc """
  Increments the kill count for a system.
  """
  def system_increment_kill_count(system_id) do
    case system_get_kill_count(system_id) do
      {:ok, current_count} ->
        new_count = current_count + 1
        system_put_kill_count(system_id, new_count)
        {:ok, new_count}
    end
  end

  @doc """
  Gets active systems list.
  """
  def system_get_active_systems do
    case get("systems", "active_list") do
      {:ok, nil} -> {:ok, []}
      {:ok, systems} when is_list(systems) -> {:ok, systems}
      # Clean up corrupted data
      {:ok, _invalid} -> {:ok, []}
      {:error, _reason} -> {:ok, []}
    end
  end

  @doc """
  Adds a system to the active systems list.
  """
  def system_add_active(system_id) do
    case system_get_active_systems() do
      {:ok, systems} ->
        if system_id in systems do
          {:ok, true}
        else
          new_systems = [system_id | systems]
          put("systems", "active_list", new_systems)
        end
    end
  end

  @doc """
  Checks if a system was recently fetched.
  """
  def system_recently_fetched?(system_id) do
    case get("systems", "last_fetch:#{system_id}") do
      {:ok, nil} ->
        false

      {:ok, timestamp} when is_integer(timestamp) ->
        current_time = System.system_time(:second)
        # Convert minutes to seconds
        threshold = Config.cache().recent_fetch_threshold * 60
        current_time - timestamp < threshold

      {:ok, _invalid} ->
        false

      {:error, _reason} ->
        false
    end
  end

  @doc """
  Marks a system as recently fetched.
  """
  def system_mark_fetched(system_id) do
    timestamp = System.system_time(:second)
    put("systems", "last_fetch:#{system_id}", timestamp)
  end

  @doc """
  Caches killmails for a system.
  """
  def cache_killmails_for_system(system_id, killmails) when is_list(killmails) do
    put("systems", "cached_killmails:#{system_id}", killmails)
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

  @doc """
  Checks if a system is in the active systems list.
  """
  def system_is_active?(system_id) do
    case system_get_active_systems() do
      {:ok, systems} ->
        {:ok, system_id in systems}
    end
  end

  @doc """
  Gets the last fetch timestamp for a system.
  """
  def system_get_fetch_timestamp(system_id) do
    case get("systems", "last_fetch:#{system_id}") do
      {:ok, nil} -> {:error, :not_found}
      {:ok, timestamp} when is_integer(timestamp) -> {:ok, timestamp}
      {:ok, _invalid} -> {:error, :invalid_data}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets the last fetch timestamp for a system.
  """
  def system_set_fetch_timestamp(system_id, %DateTime{} = timestamp) do
    system_set_fetch_timestamp(system_id, DateTime.to_unix(timestamp))
  end

  def system_set_fetch_timestamp(system_id, timestamp) when is_integer(timestamp) do
    case put("systems", "last_fetch:#{system_id}", timestamp) do
      {:ok, _} -> {:ok, :set}
      error -> error
    end
  end

  @doc """
  Checks if a system was recently fetched within a custom threshold.
  """
  def system_recently_fetched?(system_id, threshold_minutes) do
    case get("systems", "last_fetch:#{system_id}") do
      {:ok, nil} ->
        {:ok, false}

      {:ok, timestamp} when is_integer(timestamp) ->
        current_time = System.system_time(:second)
        threshold_seconds = threshold_minutes * 60
        recently_fetched = current_time - timestamp < threshold_seconds
        {:ok, recently_fetched}

      {:ok, _invalid} ->
        {:ok, false}

      {:error, _reason} ->
        {:ok, false}
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
