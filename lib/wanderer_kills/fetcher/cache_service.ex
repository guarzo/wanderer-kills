defmodule WandererKills.Fetcher.CacheService do
  @moduledoc """
  Cache management service for fetched data.

  This module handles all cache operations related to fetching,
  including checking cache freshness, storing results, and managing
  fetch timestamps. It focuses solely on cache interactions without
  API or processing logic.
  """

  require Logger
  alias WandererKills.Cache
  alias WandererKills.Infrastructure.Error

  @type system_id :: pos_integer()
  @type killmail_id :: pos_integer()
  @type killmail :: map()

  @doc """
  Gets cached killmails for a specific system.

  ## Parameters
  - `system_id` - The system ID to get killmails for

  ## Returns
  - `{:ok, [killmail_id]}` - List of cached killmail IDs for the system
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, killmail_ids} = CacheService.get_cached_killmails(30000142)
  {:ok, []} = CacheService.get_cached_killmails(99999)
  ```
  """
  @spec get_cached_killmails(system_id()) :: {:ok, [killmail_id()]} | {:error, term()}
  def get_cached_killmails(system_id) when is_integer(system_id) and system_id > 0 do
    Logger.debug("Getting cached killmails for system",
      system_id: system_id,
      operation: :get_cached_killmails,
      step: :start
    )

    case Cache.get_killmails_for_system(system_id) do
      {:ok, killmail_ids} ->
        Logger.debug("Successfully retrieved cached killmails",
          system_id: system_id,
          killmail_count: length(killmail_ids),
          operation: :get_cached_killmails,
          step: :success
        )

        {:ok, killmail_ids}

      {:error, reason} ->
        Logger.debug("Failed to retrieve cached killmails",
          system_id: system_id,
          error: reason,
          operation: :get_cached_killmails,
          step: :error
        )

        {:error, reason}
    end
  end

  def get_cached_killmails(invalid_id) do
    {:error, Error.validation_error("Invalid system ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Caches killmails for a system.

  ## Parameters
  - `system_id` - The system ID to cache killmails for
  - `killmails` - List of killmail data to cache

  ## Returns
  - `:ok` - On successful caching
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  :ok = CacheService.cache_killmails(30000142, [killmail1, killmail2])
  ```
  """
  @spec cache_killmails(system_id(), [killmail()]) :: :ok | {:error, term()}
  def cache_killmails(system_id, killmails)
      when is_integer(system_id) and system_id > 0 and is_list(killmails) do
    Logger.debug("Caching killmails for system",
      system_id: system_id,
      killmail_count: length(killmails),
      operation: :cache_killmails,
      step: :start
    )

    try do
      # Update fetch timestamp
      :ok = set_system_fetch_timestamp(system_id)

      # Extract killmail IDs and cache individual killmails
      killmail_ids =
        Enum.map(killmails, fn killmail ->
          killmail_id = Map.get(killmail, "killmail_id") || Map.get(killmail, "killID")

          if killmail_id do
            # Cache the individual killmail
            Cache.set_killmail(killmail_id, killmail)
            killmail_id
          else
            Logger.warning("Killmail missing ID during caching",
              system_id: system_id,
              killmail: inspect(killmail)
            )

            nil
          end
        end)
        |> Enum.filter(&(&1 != nil))

      # Add each killmail ID to system's killmail list
      Enum.each(killmail_ids, fn killmail_id ->
        Cache.add_system_killmail(system_id, killmail_id)
      end)

      # Add system to active list
      Cache.add_active_system(system_id)

      Logger.debug("Successfully cached killmails for system",
        system_id: system_id,
        cached_count: length(killmail_ids),
        operation: :cache_killmails,
        step: :success
      )

      :ok
    rescue
      error ->
        Logger.error("Exception while caching killmails",
          system_id: system_id,
          killmail_count: length(killmails),
          error: inspect(error),
          operation: :cache_killmails,
          step: :exception
        )

        {:error, Error.cache_error(:exception, "Exception during killmail caching")}
    end
  end

  def cache_killmails(invalid_id, _killmails) when not is_integer(invalid_id) do
    {:error, Error.validation_error("Invalid system ID format: #{inspect(invalid_id)}")}
  end

  def cache_killmails(_system_id, invalid_killmails) when not is_list(invalid_killmails) do
    {:error,
     Error.validation_error("Killmails must be a list, got: #{inspect(invalid_killmails)}")}
  end

  @doc """
  Checks if a system should have its cache refreshed.

  ## Parameters
  - `system_id` - The system ID to check
  - `since_hours` - Number of hours to consider for freshness (optional, uses default threshold)

  ## Returns
  - `{:ok, true}` - If cache should be refreshed (cache is stale or missing)
  - `{:ok, false}` - If cache is still fresh
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, true} = CacheService.should_refresh_cache?(30000142, 24)
  {:ok, false} = CacheService.should_refresh_cache?(30000142, 1)
  ```
  """
  @spec should_refresh_cache?(system_id(), pos_integer() | nil) ::
          {:ok, boolean()} | {:error, term()}
  def should_refresh_cache?(system_id, since_hours \\ nil)

  def should_refresh_cache?(system_id, since_hours)
      when is_integer(system_id) and system_id > 0 do
    Logger.debug("Checking if cache should be refreshed",
      system_id: system_id,
      since_hours: since_hours,
      operation: :should_refresh_cache,
      step: :start
    )

    case Cache.system_recently_fetched?(system_id) do
      {:ok, false} ->
        Logger.debug("System not recently fetched, should refresh cache",
          system_id: system_id,
          operation: :should_refresh_cache,
          step: :should_refresh
        )

        {:ok, true}

      {:ok, true} ->
        Logger.debug("System recently fetched, cache is fresh",
          system_id: system_id,
          operation: :should_refresh_cache,
          step: :cache_fresh
        )

        {:ok, false}

      {:error, reason} ->
        Logger.warning("Cache check failed, defaulting to refresh",
          system_id: system_id,
          error: reason,
          operation: :should_refresh_cache,
          step: :error_default_refresh
        )

        # Default to refresh on error
        {:ok, true}
    end
  end

  def should_refresh_cache?(invalid_id, _since_hours) do
    {:error, Error.validation_error("Invalid system ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Updates the fetch timestamp for a system to mark it as recently fetched.

  ## Parameters
  - `system_id` - The system ID to update
  - `timestamp` - Optional timestamp (defaults to current time)

  ## Returns
  - `:ok` - On successful update
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  :ok = CacheService.set_system_fetch_timestamp(30000142)
  :ok = CacheService.set_system_fetch_timestamp(30000142, ~U[2023-01-01 12:00:00Z])
  ```
  """
  @spec set_system_fetch_timestamp(system_id(), DateTime.t() | nil) :: :ok | {:error, term()}
  def set_system_fetch_timestamp(system_id, timestamp \\ nil)

  def set_system_fetch_timestamp(system_id, timestamp)
      when is_integer(system_id) and system_id > 0 do
    actual_timestamp = timestamp || DateTime.utc_now()

    Logger.debug("Setting system fetch timestamp",
      system_id: system_id,
      timestamp: actual_timestamp,
      operation: :set_system_fetch_timestamp,
      step: :start
    )

    case Cache.set_system_fetch_timestamp(system_id, actual_timestamp) do
      :ok ->
        Logger.debug("Successfully set system fetch timestamp",
          system_id: system_id,
          timestamp: actual_timestamp,
          operation: :set_system_fetch_timestamp,
          step: :success
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to set system fetch timestamp",
          system_id: system_id,
          timestamp: actual_timestamp,
          error: reason,
          operation: :set_system_fetch_timestamp,
          step: :error
        )

        {:error, reason}
    end
  end

  def set_system_fetch_timestamp(invalid_id, _timestamp) do
    {:error, Error.validation_error("Invalid system ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Gets the fetch timestamp for a system.

  ## Parameters
  - `system_id` - The system ID to get timestamp for

  ## Returns
  - `{:ok, timestamp}` - On success
  - `{:error, :not_found}` - If no timestamp exists
  - `{:error, reason}` - On other failures

  ## Examples

  ```elixir
  {:ok, timestamp} = CacheService.get_system_fetch_timestamp(30000142)
  {:error, :not_found} = CacheService.get_system_fetch_timestamp(99999)
  ```
  """
  @spec get_system_fetch_timestamp(system_id()) :: {:ok, DateTime.t()} | {:error, term()}
  def get_system_fetch_timestamp(system_id) when is_integer(system_id) and system_id > 0 do
    Logger.debug("Getting system fetch timestamp",
      system_id: system_id,
      operation: :get_system_fetch_timestamp,
      step: :start
    )

    case Cache.get_system_fetch_timestamp(system_id) do
      {:ok, timestamp} ->
        Logger.debug("Successfully retrieved system fetch timestamp",
          system_id: system_id,
          timestamp: timestamp,
          operation: :get_system_fetch_timestamp,
          step: :success
        )

        {:ok, timestamp}

      {:error, reason} ->
        Logger.debug("Failed to retrieve system fetch timestamp",
          system_id: system_id,
          error: reason,
          operation: :get_system_fetch_timestamp,
          step: :error
        )

        {:error, reason}
    end
  end

  def get_system_fetch_timestamp(invalid_id) do
    {:error, Error.validation_error("Invalid system ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Checks if cache exists and is recent for a system, with fallback to remote fetch.

  This is a convenience function that combines cache checking and provides
  a decision about whether to use cache or fetch remotely.

  ## Parameters
  - `system_id` - The system ID to check
  - `since_hours` - Hours threshold for cache freshness

  ## Returns
  - `{:cache, killmail_ids}` - Use cached data
  - `{:fetch, :required}` - Fetch from remote required
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:cache, killmail_ids} = CacheService.check_cache_or_fetch(30000142, 24)
  {:fetch, :required} = CacheService.check_cache_or_fetch(99999, 24)
  ```
  """
  @spec check_cache_or_fetch(system_id(), pos_integer()) ::
          {:cache, [killmail_id()]} | {:fetch, :required} | {:error, term()}
  def check_cache_or_fetch(system_id, since_hours)
      when is_integer(system_id) and system_id > 0 and is_integer(since_hours) do
    with {:ok, should_refresh} <- should_refresh_cache?(system_id, since_hours) do
      case should_refresh do
        false ->
          # Cache is fresh, get cached data
          case get_cached_killmails(system_id) do
            {:ok, killmail_ids} -> {:cache, killmail_ids}
            {:error, reason} -> {:error, reason}
          end

        true ->
          # Cache is stale or missing, need to fetch
          {:fetch, :required}
      end
    end
  end

  def check_cache_or_fetch(invalid_id, _since_hours) do
    {:error, Error.validation_error("Invalid system ID format: #{inspect(invalid_id)}")}
  end
end
