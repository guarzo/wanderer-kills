defmodule WandererKills.Cache.Systems do
  @moduledoc """
  Domain-specific cache wrapper for system data.

  This module encapsulates all Cachex operations for systems,
  providing a clean interface for business logic without direct
  Cachex dependencies.
  """

  alias WandererKills.Core.{Config, Error, Clock}
  require Logger

  @cache_name :systems

  @doc """
  Generates a cache key for system data.
  """
  @spec key(atom(), integer()) :: String.t()
  def key(type, system_id) when is_atom(type) and is_integer(system_id) do
    "system:#{type}:#{system_id}"
  end

  @doc """
  Gets system killmails from cache.
  """
  @spec get_killmails(integer()) :: {:ok, [integer()]} | {:error, Error.t()}
  def get_killmails(system_id) when is_integer(system_id) do
    cache_key = key(:killmails, system_id)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        {:error, Error.cache_error(:not_found, "System killmails not found in cache")}

      {:ok, killmail_ids} when is_list(killmail_ids) ->
        {:ok, killmail_ids}

      {:ok, _invalid_data} ->
        # Clean up corrupted data
        Cachex.del(@cache_name, cache_key)
        {:error, Error.cache_error(:invalid_data, "Corrupted system killmails data")}

      {:error, reason} ->
        Logger.error("Cache get failed", key: cache_key, reason: inspect(reason))
        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @doc """
  Adds a killmail ID to a system's killmail list.
  """
  @spec add_killmail(integer(), integer()) :: :ok | {:error, Error.t()}
  def add_killmail(system_id, killmail_id)
      when is_integer(system_id) and is_integer(killmail_id) do
    case get_killmails(system_id) do
      {:ok, existing_ids} ->
        if killmail_id not in existing_ids do
          new_ids = [killmail_id | existing_ids]
          put_killmails(system_id, new_ids)
        else
          :ok
        end

      {:error, %Error{type: :not_found}} ->
        put_killmails(system_id, [killmail_id])

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Puts system killmails in cache.
  """
  @spec put_killmails(integer(), [integer()]) :: :ok | {:error, Error.t()}
  def put_killmails(system_id, killmail_ids)
      when is_integer(system_id) and is_list(killmail_ids) do
    cache_key = key(:killmails, system_id)
    ttl_ms = Config.cache_ttl(:system) * 1000

    case Cachex.put(@cache_name, cache_key, killmail_ids, ttl: ttl_ms) do
      {:ok, true} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache put failed", key: cache_key, reason: inspect(reason))
        {:error, Error.cache_error(:put_failed, "Failed to put in cache", %{reason: reason})}
    end
  end

  @doc """
  Checks if a system is active.
  """
  @spec is_active?(integer()) :: {:ok, boolean()} | {:error, Error.t()}
  def is_active?(system_id) when is_integer(system_id) do
    cache_key = key(:active, system_id)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        {:ok, false}

      {:ok, _timestamp} ->
        {:ok, true}

      {:error, reason} ->
        Logger.error("Cache get failed", key: cache_key, reason: inspect(reason))
        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @doc """
  Adds a system to the active systems list.
  """
  @spec add_active(integer()) :: {:ok, :added | :already_exists} | {:error, Error.t()}
  def add_active(system_id) when is_integer(system_id) do
    cache_key = key(:active, system_id)
    timestamp = Clock.now()
    ttl_ms = Config.cache_ttl(:system) * 1000

    case is_active?(system_id) do
      {:ok, true} ->
        {:ok, :already_exists}

      {:ok, false} ->
        case Cachex.put(@cache_name, cache_key, timestamp, ttl: ttl_ms) do
          {:ok, true} ->
            {:ok, :added}

          {:error, reason} ->
            Logger.error("Cache put failed", key: cache_key, reason: inspect(reason))
            {:error, Error.cache_error(:put_failed, "Failed to put in cache", %{reason: reason})}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets all active system IDs.
  """
  @spec get_active_systems() :: {:ok, [integer()]} | {:error, Error.t()}
  def get_active_systems do
    case Cachex.stream(@cache_name, "system:active:*") do
      {:ok, stream} ->
        system_ids =
          stream
          |> Enum.map(fn {key, _value} ->
            # Extract system_id from "system:active:12345" format
            case String.split(key, ":") do
              ["system", "active", system_id_str] ->
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
        Logger.error("Cache stream failed", reason: inspect(reason))

        {:error,
         Error.cache_error(:stream_failed, "Failed to stream from cache", %{reason: reason})}
    end
  end

  @doc """
  Gets system fetch timestamp.
  """
  @spec get_fetch_timestamp(integer()) :: {:ok, DateTime.t()} | {:error, Error.t()}
  def get_fetch_timestamp(system_id) when is_integer(system_id) do
    cache_key = key(:fetch_timestamp, system_id)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        {:error,
         Error.not_found_error("No fetch timestamp found for system", %{system_id: system_id})}

      {:ok, timestamp} when is_struct(timestamp, DateTime) ->
        {:ok, timestamp}

      {:ok, _invalid_data} ->
        # Clean up corrupted data
        Cachex.del(@cache_name, cache_key)
        {:error, Error.cache_error(:invalid_data, "Corrupted timestamp data")}

      {:error, reason} ->
        Logger.error("Cache get failed", key: cache_key, reason: inspect(reason))
        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @doc """
  Sets system fetch timestamp.
  """
  @spec set_fetch_timestamp(integer(), DateTime.t() | nil) :: {:ok, :set} | {:error, Error.t()}
  def set_fetch_timestamp(system_id, timestamp \\ nil) when is_integer(system_id) do
    cache_key = key(:fetch_timestamp, system_id)
    timestamp = timestamp || Clock.now()
    ttl_ms = Config.cache_ttl(:system) * 1000

    case Cachex.put(@cache_name, cache_key, timestamp, ttl: ttl_ms) do
      {:ok, true} ->
        {:ok, :set}

      {:error, reason} ->
        Logger.error("Cache put failed", key: cache_key, reason: inspect(reason))
        {:error, Error.cache_error(:put_failed, "Failed to put in cache", %{reason: reason})}
    end
  end

  @doc """
  Checks if a system was recently fetched.
  """
  @spec recently_fetched?(integer(), pos_integer()) :: {:ok, boolean()} | {:error, Error.t()}
  def recently_fetched?(system_id, threshold_hours \\ 1)
      when is_integer(system_id) and is_integer(threshold_hours) do
    case get_fetch_timestamp(system_id) do
      {:ok, timestamp} ->
        cutoff_time = Clock.now() |> DateTime.add(-threshold_hours * 3600, :second)
        is_recent = DateTime.compare(timestamp, cutoff_time) == :gt
        {:ok, is_recent}

      {:error, %Error{type: :not_found}} ->
        {:ok, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets system kill count.
  """
  @spec get_kill_count(integer()) :: {:ok, integer()} | {:error, Error.t()}
  def get_kill_count(system_id) when is_integer(system_id) do
    cache_key = key(:kill_count, system_id)

    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        {:ok, 0}

      {:ok, count} when is_integer(count) ->
        {:ok, count}

      {:ok, _invalid_data} ->
        # Clean up corrupted data and return 0
        Cachex.del(@cache_name, cache_key)
        {:ok, 0}

      {:error, reason} ->
        Logger.error("Cache get failed", key: cache_key, reason: inspect(reason))
        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @doc """
  Increments system kill count.
  """
  @spec increment_kill_count(integer()) :: {:ok, integer()} | {:error, Error.t()}
  def increment_kill_count(system_id) when is_integer(system_id) do
    cache_key = key(:kill_count, system_id)
    ttl_ms = Config.cache_ttl(:system) * 1000

    case get_kill_count(system_id) do
      {:ok, current_count} ->
        new_count = current_count + 1

        case Cachex.put(@cache_name, cache_key, new_count, ttl: ttl_ms) do
          {:ok, true} ->
            {:ok, new_count}

          {:error, reason} ->
            Logger.error("Cache put failed", key: cache_key, reason: inspect(reason))
            {:error, Error.cache_error(:put_failed, "Failed to put in cache", %{reason: reason})}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Clears all system data from cache.
  """
  @spec clear() :: :ok | {:error, Error.t()}
  def clear do
    case Cachex.clear(@cache_name) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Cache clear failed", reason: inspect(reason))
        {:error, Error.cache_error(:clear_failed, "Failed to clear cache", %{reason: reason})}
    end
  end

  @doc """
  Gets cache statistics as a list.
  """
  @spec stats() :: [map()]
  def stats do
    case Cachex.stats(@cache_name) do
      {:ok, stats} ->
        [Map.put(stats, :cache_name, @cache_name)]

      {:error, _reason} ->
        [%{cache_name: @cache_name, error: true}]
    end
  end
end
