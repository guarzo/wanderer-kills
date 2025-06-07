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

    try do
      case Cachex.stream(@cache_name, pattern) do
        {:ok, stream} ->
          stream
          |> Stream.each(fn {key, _value} -> Cachex.del(@cache_name, key) end)
          |> Stream.run()

          :ok

        stream when is_struct(stream, Stream) ->
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

  # ============================================================================
  # Domain-Specific Convenience Functions
  # ============================================================================

  @doc """
  Character cache operations.
  """
  def character_get(id), do: get_with_error("characters", to_string(id))
  def character_put(id, data), do: put("characters", to_string(id), data)

  def character_get_or_set(id, fallback_fn),
    do: get_or_set("characters", to_string(id), fallback_fn)

  def character_delete(id), do: delete("characters", to_string(id))

  @doc """
  Corporation cache operations.
  """
  def corporation_get(id), do: get_with_error("corporations", to_string(id))
  def corporation_put(id, data), do: put("corporations", to_string(id), data)

  def corporation_get_or_set(id, fallback_fn),
    do: get_or_set("corporations", to_string(id), fallback_fn)

  def corporation_delete(id), do: delete("corporations", to_string(id))

  @doc """
  Alliance cache operations.
  """
  def alliance_get(id), do: get_with_error("alliances", to_string(id))
  def alliance_put(id, data), do: put("alliances", to_string(id), data)

  def alliance_get_or_set(id, fallback_fn),
    do: get_or_set("alliances", to_string(id), fallback_fn)

  def alliance_delete(id), do: delete("alliances", to_string(id))

  @doc """
  ESI-specific cache operations (legacy compatibility).
  These functions provide direct ESI cache access for modules that expect ESI-prefixed functions.
  """
  def esi_get_character(id), do: character_get(id)
  def esi_get_corporation(id), do: corporation_get(id)
  def esi_get_alliance(id), do: alliance_get(id)

  def esi_get_or_set_character(id, fallback_fn), do: character_get_or_set(id, fallback_fn)
  def esi_get_or_set_corporation(id, fallback_fn), do: corporation_get_or_set(id, fallback_fn)
  def esi_get_or_set_alliance(id, fallback_fn), do: alliance_get_or_set(id, fallback_fn)
  def esi_get_or_set_type(id, fallback_fn), do: ship_type_get_or_set(id, fallback_fn)
  def esi_get_or_set_group(id, fallback_fn), do: get_or_set("groups", to_string(id), fallback_fn)
  def esi_get_or_set_killmail(id, fallback_fn), do: killmail_get_or_set(id, fallback_fn)

  @doc """
  Ship type cache operations.
  """
  def ship_type_get(id), do: get_with_error("ship_types", to_string(id))
  def ship_type_put(id, data), do: put("ship_types", to_string(id), data)

  def ship_type_get_or_set(id, fallback_fn),
    do: get_or_set("ship_types", to_string(id), fallback_fn)

  def ship_type_delete(id), do: delete("ship_types", to_string(id))

  @doc """
  System cache operations.
  """
  def system_get(id), do: get_with_error("systems", to_string(id))
  def system_put(id, data), do: put("systems", to_string(id), data)
  def system_get_or_set(id, fallback_fn), do: get_or_set("systems", to_string(id), fallback_fn)
  def system_delete(id), do: delete("systems", to_string(id))

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
        if killmail_id not in existing_ids do
          new_ids = [killmail_id | existing_ids]
          system_put_killmails(system_id, new_ids)
        else
          {:ok, true}
        end

      {:error, :not_found} ->
        system_put_killmails(system_id, [killmail_id])

      {:error, reason} ->
        {:error, reason}
    end
  end

  def system_is_active?(system_id) do
    case get("systems", "active:#{system_id}") do
      {:ok, nil} -> {:ok, false}
      {:ok, _timestamp} -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  def system_add_active(system_id) do
    case system_is_active?(system_id) do
      {:ok, true} ->
        {:ok, :already_exists}

      {:ok, false} ->
        timestamp = DateTime.utc_now()

        case put("systems", "active:#{system_id}", timestamp) do
          {:ok, true} -> {:ok, :added}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def system_get_fetch_timestamp(system_id) do
    case get("systems", "fetch_timestamp:#{system_id}") do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, timestamp} when is_struct(timestamp, DateTime) ->
        {:ok, timestamp}

      {:ok, _invalid_data} ->
        # Clean up corrupted data
        delete("systems", "fetch_timestamp:#{system_id}")
        {:error, :invalid_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def system_set_fetch_timestamp(system_id, timestamp \\ nil) do
    timestamp = timestamp || DateTime.utc_now()

    case put("systems", "fetch_timestamp:#{system_id}", timestamp) do
      {:ok, true} -> {:ok, :set}
      {:error, reason} -> {:error, reason}
    end
  end

  def system_get_kill_count(system_id) do
    case get("systems", "kill_count:#{system_id}") do
      {:ok, nil} ->
        {:ok, 0}

      {:ok, count} when is_integer(count) ->
        {:ok, count}

      {:ok, _invalid_data} ->
        # Clean up corrupted data and return 0
        delete("systems", "kill_count:#{system_id}")
        {:ok, 0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def system_increment_kill_count(system_id) do
    case system_get_kill_count(system_id) do
      {:ok, current_count} ->
        new_count = current_count + 1

        case put("systems", "kill_count:#{system_id}", new_count) do
          {:ok, true} -> {:ok, new_count}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def system_get_active_systems do
    case stream("systems", "active:*") do
      {:ok, stream} ->
        system_ids =
          stream
          |> Enum.map(fn {key, _value} ->
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
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        {:ok, system_ids}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def system_recently_fetched?(system_id, threshold_hours \\ 1) do
    case system_get_fetch_timestamp(system_id) do
      {:ok, timestamp} ->
        cutoff_time = DateTime.utc_now() |> DateTime.add(-threshold_hours * 3600, :second)
        is_recent = DateTime.compare(timestamp, cutoff_time) == :gt
        {:ok, is_recent}

      {:error, :not_found} ->
        {:ok, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Killmail cache operations.
  """
  def killmail_get(id), do: get_with_error("killmails", to_string(id))
  def killmail_put(id, data), do: put("killmails", to_string(id), data)

  def killmail_get_or_set(id, fallback_fn),
    do: get_or_set("killmails", to_string(id), fallback_fn)

  def killmail_delete(id), do: delete("killmails", to_string(id))

  @doc """
  Caches killmails for a specific system.

  This function:
  1. Updates the system's fetch timestamp
  2. Caches individual killmails by ID
  3. Associates killmail IDs with the system
  4. Adds the system to the active systems list

  ## Parameters
  - `system_id` - The solar system ID
  - `killmails` - List of killmail maps

  ## Returns
  - `:ok` on success
  - `{:error, :cache_exception}` on failure
  """
  @spec cache_killmails_for_system(integer(), [map()]) :: :ok | {:error, term()}
  def cache_killmails_for_system(system_id, killmails) when is_list(killmails) do
    try do
      # Update fetch timestamp
      case system_set_fetch_timestamp(system_id, DateTime.utc_now()) do
        {:ok, _} -> :ok
        # Continue anyway
        {:error, _reason} -> :ok
      end

      # Extract killmail IDs and cache individual killmails
      killmail_ids =
        killmails
        |> Enum.map(fn killmail ->
          killmail_id = Map.get(killmail, "killmail_id") || Map.get(killmail, "killID")

          if killmail_id do
            # Cache the individual killmail
            killmail_put(killmail_id, killmail)
            killmail_id
          else
            nil
          end
        end)
        |> Enum.filter(&(&1 != nil))

      # Add each killmail ID to system's killmail list
      Enum.each(killmail_ids, fn killmail_id ->
        system_add_killmail(system_id, killmail_id)
      end)

      # Add system to active list
      system_add_active(system_id)

      :ok
    rescue
      _error -> {:error, :cache_exception}
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
