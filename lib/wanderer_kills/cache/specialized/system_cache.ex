defmodule WandererKills.Cache.Specialized.SystemCache do
  @moduledoc """
  Cache module for system data.

  This module provides functions for caching and retrieving system data,
  using the centralized TTL configuration from the application config.

  ## Features

  - System data caching
  - TTL management
  - Cache key generation
  - Error handling

  ## Configuration

  System cache configuration is managed through application config:

  ```elixir
  config :wanderer_kills,
    cache: %{
      system: [name: :system_cache, ttl: :timer.hours(1)]
    }
  ```

  ## Usage

  ```elixir
  # Cache system data
  :ok = cache_system_data(123, %{name: "Jita"})

  # Get system data
  {:ok, data} = get_system_data(123)
  ```
  """

  require Logger
  alias WandererKills.Cache.Base
  alias WandererKills.Cache.Key
  alias WandererKills.Core.Clock
  alias WandererKills.Core.Config
  alias Cachex

  @type cache_result :: {:ok, term()} | {:error, term()}
  @type cache_status :: :ok | {:error, term()}
  @type system_id :: pos_integer()
  @type system_data :: map()

  @doc """
  Gets all killmails for a system.
  """
  @spec get_killmails_for_system(integer()) :: cache_result()
  def get_killmails_for_system(system_id) do
    Base.get_list(:system, Key.system_killmails_key(system_id))
  end

  @doc """
  Gets all killmail IDs for a system.
  """
  @spec get_killmail_ids_for_system(integer()) :: cache_result()
  def get_killmail_ids_for_system(system_id) do
    Base.get_list(:system, Key.system_killmails_key(system_id, :killmail_ids))
  end

  @doc """
  Adds a killmail ID to a system's killmail list using configured TTL.
  """
  @spec add_system_killmail(integer(), integer()) :: cache_status()
  def add_system_killmail(system_id, killmail_id) do
    ttl = Config.cache(:system, :ttl)
    Base.add_to_list(:system, Key.system_killmails_key(system_id), killmail_id, ttl)
  end

  @doc """
  Removes a killmail ID from a system's killmail list using configured TTL.
  """
  @spec remove_system_killmail(integer(), integer()) :: cache_status()
  def remove_system_killmail(system_id, killmail_id) do
    Base.remove_from_list(:system, Key.system_killmails_key(system_id), killmail_id)
  end

  @doc """
  Checks if a system was recently fetched.
  """
  @spec recently_fetched?(integer()) :: {:ok, boolean()} | {:error, term()}
  def recently_fetched?(system_id) do
    case Base.get_value(:system, Key.system_fetch_timestamp_key(system_id)) do
      {:ok, nil} ->
        {:ok, false}

      {:ok, timestamp} ->
        threshold = Config.recent_fetch_threshold()
        now = System.system_time(:second)
        {:ok, now - timestamp < threshold}

      error ->
        error
    end
  end

  @doc """
  Stores the timestamp of when a system was last fetched using configured TTL.
  """
  @spec set_fetch_timestamp(integer()) :: cache_status()
  def set_fetch_timestamp(system_id) do
    Base.set_value(
      :system,
      Key.system_fetch_timestamp_key(system_id),
      System.system_time(:second)
    )
  end

  @doc """
  Stores a specific timestamp for when a system was last fetched.
  """
  @spec set_fetch_timestamp(integer(), DateTime.t() | integer()) :: cache_status()
  def set_fetch_timestamp(system_id, %DateTime{} = timestamp) do
    unix_timestamp = DateTime.to_unix(timestamp, :microsecond)

    Base.set_value(
      :system,
      Key.system_fetch_timestamp_key(system_id),
      unix_timestamp
    )
  end

  def set_fetch_timestamp(system_id, unix_timestamp) when is_integer(unix_timestamp) do
    Base.set_value(
      :system,
      Key.system_fetch_timestamp_key(system_id),
      unix_timestamp
    )
  end

  @doc """
  Gets the fetch timestamp for a system.
  """
  @spec get_fetch_timestamp(integer()) :: {:ok, DateTime.t() | nil} | {:error, term()}
  def get_fetch_timestamp(system_id) do
    case Base.get_value(:system, Key.system_fetch_timestamp_key(system_id)) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, unix_timestamp} when is_integer(unix_timestamp) ->
        {:ok, DateTime.from_unix!(unix_timestamp, :microsecond)}

      error ->
        error
    end
  end

  @doc """
  Increments the kill count for a system using configured TTL.
  """
  @spec increment_kill_count(integer()) :: cache_status()
  def increment_kill_count(system_id) do
    Base.increment_counter(:system, Key.system_kill_count_key(system_id))
  end

  @doc """
  Decrements the kill count for a system using configured TTL.
  """
  @spec decrement_kill_count(integer()) :: cache_status()
  def decrement_kill_count(system_id) do
    Base.decrement_counter(:system, Key.system_kill_count_key(system_id))
  end

  @doc """
  Gets the kill count for a system.
  """
  @spec get_system_kill_count(integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_system_kill_count(system_id) do
    Base.get_counter(:system, Key.system_kill_count_key(system_id))
  end

  @doc """
  Updates the TTL for a system's data using configured TTL.
  """
  @spec update_ttl(integer()) :: cache_status()
  def update_ttl(system_id) do
    Base.set_value(
      :system,
      Key.system_ttl_key(system_id),
      Clock.now_milliseconds()
    )
  end

  @doc """
  Caches system data for a given system ID.

  ## Parameters
  - `system_id` - The system ID
  - `data` - The system data to cache

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = cache_system_data(123, %{name: "Jita"})
  ```
  """
  @spec cache_system_data(system_id(), system_data()) :: cache_status()
  def cache_system_data(system_id, data) do
    key = Key.system_data_key(system_id)
    Base.set_value(:system, key, data)
  end

  @doc """
  Gets cached system data for a given system ID.

  ## Parameters
  - `system_id` - The system ID

  ## Returns
  - `{:ok, data}` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, data} = get_system_data(123)
  ```
  """
  @spec get_system_data(system_id()) :: {:ok, system_data()} | {:error, term()}
  def get_system_data(system_id) do
    key = Key.system_data_key(system_id)
    Base.get_value(:system, key)
  end

  @doc """
  Gets the list of active systems.
  """
  @spec get_active_systems() :: {:ok, [system_id()]} | {:error, term()}
  def get_active_systems do
    Base.get_list(:system, Key.active_systems_key())
  end

  @doc """
  Adds a system to the active systems list.

  ## Parameters
  - `system_id` - The system ID to add

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = add_active_system(123)
  ```
  """
  @spec add_active_system(system_id()) :: cache_status()
  def add_active_system(system_id) do
    case Base.add_to_list(:system, Key.active_systems_key(), system_id) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Removes a system from the active systems list.

  ## Parameters
  - `system_id` - The system ID to remove

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = remove_active_system(123)
  ```
  """
  @spec remove_active_system(system_id()) :: cache_status()
  def remove_active_system(system_id) do
    case Base.remove_from_list(:system, Key.active_systems_key(), system_id) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Adds a killmail ID to a system's killmail ID list using configured TTL.
  """
  @spec add_system_killmail_id(integer(), integer()) :: cache_status()
  def add_system_killmail_id(system_id, killmail_id) do
    ttl = Config.cache(:system, :ttl)

    Base.add_to_list(
      :system,
      Key.system_killmails_key(system_id, :killmail_ids),
      killmail_id,
      ttl
    )
  end

  @doc """
  Removes a killmail ID from a system's killmail ID list using configured TTL.
  """
  @spec remove_system_killmail_id(integer(), integer()) :: cache_status()
  def remove_system_killmail_id(system_id, killmail_id) do
    Base.remove_from_list(
      :system,
      Key.system_killmails_key(system_id, :killmail_ids),
      killmail_id
    )
  end

  @doc """
  Clears the system cache.
  """
  @spec clear() :: cache_status()
  def clear do
    Base.clear(:system)
  end
end
