defmodule WandererKills.Cache.Base do
  @moduledoc """
  Base module for cache operations.

  This module provides common functionality for all cache operations,
  including configuration management and basic cache operations.

  ## Features

  - Centralized cache configuration
  - TTL management
  - Basic cache operations (get, set, delete)
  - Error handling and logging

  ## Configuration

  Cache configuration is managed through application config:

  ```elixir
  config :wanderer_kills,
    cache: %{
      killmails: [name: :killmails_cache, ttl: :timer.hours(24)],
      system: [name: :system_cache, ttl: :timer.hours(1)],
      esi: [name: :esi_cache, ttl: :timer.hours(48)]
    }
  ```

  ## Usage

  ```elixir
  # Get cache configuration
  config = Base.get_cache_config(:killmails)

  # Set a value with TTL
  Base.set_value(:killmails, "key", value)

  # Get a value
  {:ok, value} = Base.get_value(:killmails, "key")
  ```
  """

  require Logger
  alias WandererKills.Cache.Errors
  alias WandererKills.Config

  @type cache_type :: :killmails | :system | :esi
  @type cache_name :: atom()
  @type cache_key :: String.t()
  @type cache_value :: term()
  @type cache_status :: :ok | Errors.cache_error()
  @type cache_config :: %{name: atom(), ttl: pos_integer()}
  @type cache_result :: {:ok, cache_value()} | Errors.cache_error()

  @doc """
  Gets the cache configuration for a given cache type.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)

  ## Returns
  A map containing:
  - `:name` - The cache name
  - `:ttl` - The TTL in milliseconds

  ## Example

  ```elixir
  config = get_cache_config(:killmails)
  # %{name: :killmails_cache, ttl: 86400000}
  ```
  """
  @spec get_cache_config(cache_type()) :: cache_config()
  def get_cache_config(cache_type) do
    Config.cache(cache_type)
  end

  @doc """
  Gets a value from the cache.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key

  ## Returns
  - `{:ok, value}` - On success
  - `{:ok, nil}` - When key is not found
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, value} = get_value(:killmails, "key")
  {:ok, nil} = get_value(:killmails, "non_existent_key")
  ```
  """
  @spec get_value(cache_type(), cache_key()) :: {:ok, cache_value()} | {:error, term()}
  def get_value(cache_type, key) do
    %{name: cache_name} = get_cache_config(cache_type)

    case Cachex.get(cache_name, key) do
      {:ok, nil} -> {:ok, nil}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets a value in the cache with the configured TTL.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key
  - `value` - The value to store

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = set_value(:killmails, "key", value)
  ```
  """
  @spec set_value(cache_type(), cache_key(), cache_value()) :: cache_status()
  def set_value(cache_type, key, value) do
    %{name: cache_name, ttl: ttl} = get_cache_config(cache_type)

    case Cachex.put(cache_name, key, value, ttl: ttl) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :put_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets a value in the cache with a custom TTL.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key
  - `value` - The value to store
  - `ttl` - Custom TTL in milliseconds

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = set_value(:killmails, "key", value, :timer.minutes(30))
  ```
  """
  @spec set_value(cache_type(), cache_key(), cache_value(), pos_integer()) :: cache_status()
  def set_value(cache_type, key, value, ttl) do
    %{name: cache_name} = get_cache_config(cache_type)

    case Cachex.put(cache_name, key, value, ttl: ttl) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, :put_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a value from the cache.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = delete_value(:killmails, "key")
  ```
  """
  @spec delete_value(cache_type(), cache_key()) :: cache_status()
  def delete_value(cache_type, key) do
    %{name: cache_name} = get_cache_config(cache_type)

    case Cachex.del(cache_name, key) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a value in the cache using a function.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key
  - `update_fn` - Function to update the value

  ## Returns
  - `{:ok, new_value}` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, new_value} = update_value(:killmails, "key", &Map.put(&1, :count, 1))
  ```
  """
  @spec update_value(cache_type(), cache_key(), (cache_value() -> cache_value())) ::
          {:ok, cache_value()} | {:error, term()}
  def update_value(cache_type, key, update_fn) do
    %{name: cache_name, ttl: ttl} = get_cache_config(cache_type)

    case Cachex.update(cache_name, key, update_fn, ttl: ttl) do
      {:ok, new_value} -> {:ok, new_value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Increments a numeric value in the cache.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key
  - `amount` - The amount to increment by (default: 1)
  - `initial` - Initial value if key doesn't exist (default: 0)

  ## Returns
  - `{:ok, new_value}` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, 1} = increment_value(:system, "kill_count", 1, 0)
  {:ok, 3} = increment_value(:system, "kill_count", 2)
  ```
  """
  @spec increment_value(cache_type(), cache_key(), integer(), integer()) ::
          {:ok, integer()} | {:error, term()}
  def increment_value(cache_type, key, amount \\ 1, initial \\ 0) do
    %{name: cache_name, ttl: ttl} = get_cache_config(cache_type)

    case Cachex.incr(cache_name, key, amount, initial: initial, ttl: ttl) do
      {:ok, new_value} -> {:ok, new_value}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets a list from cache, returning empty list if not found.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key

  ## Returns
  - `{:ok, list}` - The list from cache or empty list if not found
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, []} = get_list(:system, "empty_key")
  {:ok, [1, 2, 3]} = get_list(:system, "list_key")
  ```
  """
  @spec get_list(cache_type(), cache_key()) :: {:ok, list()} | {:error, term()}
  def get_list(cache_type, key) do
    case get_value(cache_type, key) do
      {:ok, nil} -> {:ok, []}
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, _non_list} -> {:ok, []}
      error -> error
    end
  end

  @doc """
  Adds a value to a list in the cache, ensuring uniqueness.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key
  - `value` - The value to add

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = add_to_list(:killmails, "key", value)
  ```
  """
  @spec add_to_list(cache_type(), cache_key(), cache_value()) :: cache_status()
  def add_to_list(cache_type, key, value) do
    case get_list(cache_type, key) do
      {:ok, list} ->
        new_list = [value | list] |> Enum.uniq()
        set_value(cache_type, key, new_list)

      error ->
        error
    end
  end

  @doc """
  Removes a value from a list in the cache.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key
  - `value` - The value to remove

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = remove_from_list(:killmails, "key", value)
  ```
  """
  @spec remove_from_list(cache_type(), cache_key(), cache_value()) :: cache_status()
  def remove_from_list(cache_type, key, value) do
    case get_list(cache_type, key) do
      {:ok, list} ->
        new_list = Enum.reject(list, &(&1 == value))
        set_value(cache_type, key, new_list)

      error ->
        error
    end
  end

  @doc """
  Clears all entries from the configured cache.
  """
  @spec clear(atom()) :: cache_status()
  def clear(cache_type) do
    %{name: cache_name} = get_cache_config(cache_type)

    case Cachex.clear(cache_name) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the size of the configured cache.
  """
  @spec size(atom()) :: {:ok, non_neg_integer()} | {:error, term()}
  def size(cache_type) do
    %{name: cache_name} = get_cache_config(cache_type)
    Cachex.size(cache_name)
  end

  @doc """
  Gets cache statistics for the configured cache.
  """
  @spec stats(atom()) :: {:ok, map()} | {:error, term()}
  def stats(cache_type) do
    %{name: cache_name} = get_cache_config(cache_type)
    Cachex.stats(cache_name)
  end
end
