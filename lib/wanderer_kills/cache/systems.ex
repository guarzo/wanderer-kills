defmodule WandererKills.Cache.Systems do
  @moduledoc """
  Domain-specific cache wrapper for system data.

  **DEPRECATED**: This module is now a thin wrapper around `WandererKills.Cache.Helper`.
  Use `Helper.system_*` functions directly for new code.

  This module encapsulates all Cachex operations for systems,
  providing a clean interface for business logic without direct
  Cachex dependencies.
  """

  alias WandererKills.Core.Error
  alias WandererKills.Cache.Helper

  @doc """
  Generates a cache key for system data.
  """
  @spec key(atom(), integer()) :: String.t()
  def key(type, system_id) when is_atom(type) and is_integer(system_id) do
    "systems:#{type}:#{system_id}"
  end

  @doc """
  Gets system killmails from cache.
  """
  @spec get_killmails(integer()) :: {:ok, [integer()]} | {:error, term()}
  def get_killmails(system_id) when is_integer(system_id) do
    case Helper.system_get_killmails(system_id) do
      {:error, :not_found} ->
        {:error, Error.cache_error(:not_found, "System killmails not found in cache")}

      {:error, :invalid_data} ->
        {:error, Error.cache_error(:invalid_data, "Corrupted system killmails data")}

      other ->
        other
    end
  end

  @doc """
  Adds a killmail ID to a system's killmail list.
  """
  @spec add_killmail(integer(), integer()) :: :ok | {:error, term()}
  def add_killmail(system_id, killmail_id)
      when is_integer(system_id) and is_integer(killmail_id) do
    case Helper.system_add_killmail(system_id, killmail_id) do
      {:ok, true} -> :ok
      other -> other
    end
  end

  @doc """
  Puts system killmails in cache.
  """
  @spec put_killmails(integer(), [integer()]) :: :ok | {:error, term()}
  def put_killmails(system_id, killmail_ids)
      when is_integer(system_id) and is_list(killmail_ids) do
    case Helper.system_put_killmails(system_id, killmail_ids) do
      {:ok, true} -> :ok
      other -> other
    end
  end

  @doc """
  Checks if a system is active.
  """
  @spec is_active?(integer()) :: {:ok, boolean()} | {:error, term()}
  def is_active?(system_id) when is_integer(system_id) do
    Helper.system_is_active?(system_id)
  end

  @doc """
  Adds a system to the active systems list.
  """
  @spec add_active(integer()) :: {:ok, :added | :already_exists} | {:error, term()}
  def add_active(system_id) when is_integer(system_id) do
    Helper.system_add_active(system_id)
  end

  @doc """
  Gets all active system IDs.
  """
  @spec get_active_systems() :: {:ok, [integer()]} | {:error, term()}
  def get_active_systems do
    Helper.system_get_active_systems()
  end

  @doc """
  Gets system fetch timestamp.
  """
  @spec get_fetch_timestamp(integer()) :: {:ok, DateTime.t()} | {:error, term()}
  def get_fetch_timestamp(system_id) when is_integer(system_id) do
    case Helper.system_get_fetch_timestamp(system_id) do
      {:error, :not_found} ->
        {:error,
         Error.not_found_error("No fetch timestamp found for system", %{system_id: system_id})}

      {:error, :invalid_data} ->
        {:error, Error.cache_error(:invalid_data, "Corrupted timestamp data")}

      other ->
        other
    end
  end

  @doc """
  Sets system fetch timestamp.
  """
  @spec set_fetch_timestamp(integer(), DateTime.t() | nil) :: {:ok, :set} | {:error, term()}
  def set_fetch_timestamp(system_id, timestamp \\ nil) when is_integer(system_id) do
    Helper.system_set_fetch_timestamp(system_id, timestamp)
  end

  @doc """
  Checks if a system was recently fetched.
  """
  @spec recently_fetched?(integer(), pos_integer()) :: {:ok, boolean()} | {:error, term()}
  def recently_fetched?(system_id, threshold_hours \\ 1)
      when is_integer(system_id) and is_integer(threshold_hours) do
    Helper.system_recently_fetched?(system_id, threshold_hours)
  end

  @doc """
  Gets system kill count.
  """
  @spec get_kill_count(integer()) :: {:ok, integer()} | {:error, term()}
  def get_kill_count(system_id) when is_integer(system_id) do
    Helper.system_get_kill_count(system_id)
  end

  @doc """
  Increments system kill count.
  """
  @spec increment_kill_count(integer()) :: {:ok, integer()} | {:error, term()}
  def increment_kill_count(system_id) when is_integer(system_id) do
    Helper.system_increment_kill_count(system_id)
  end

  @doc """
  Clears all system data from cache.
  """
  @spec clear() :: :ok | {:error, term()}
  def clear do
    Helper.clear_namespace("systems")
    :ok
  rescue
    error -> {:error, error}
  end

  @doc """
  Gets cache statistics as a list.
  """
  @spec stats() :: [map()]
  def stats do
    case Helper.stats() do
      {:ok, stats} ->
        [Map.put(stats, :cache_name, :wanderer_cache)]

      {:error, _reason} ->
        [%{cache_name: :wanderer_cache, error: true}]
    end
  end
end
