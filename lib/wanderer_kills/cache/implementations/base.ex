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
  alias WandererKills.Core.Config

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
  @spec get_value(cache_type(), cache_key()) :: cache_result()
  def get_value(cache_type, key) do
    Cachex.get(cache_name(cache_type), namespaced_key(cache_type, key))
  end

  @doc """
  Sets a value in the cache with TTL.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key
  - `value` - The value to store
  - `ttl` - The TTL in milliseconds

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = set_value(:killmails, "key", value)
  ```
  """
  @spec set_value(cache_type(), cache_key(), cache_value(), pos_integer() | nil) :: cache_status()
  def set_value(cache_type, key, value, ttl \\ nil) do
    ttl_ms = if ttl, do: ttl * 1000, else: get_ttl(cache_type) * 1000
    Cachex.put(cache_name(cache_type), namespaced_key(cache_type, key), value, ttl: ttl_ms)
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
    Cachex.del(cache_name(cache_type), namespaced_key(cache_type, key))
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
  @spec get_list(cache_type(), cache_key()) :: cache_result()
  def get_list(cache_type, key) do
    case get_value(cache_type, key) do
      {:ok, nil} -> {:ok, []}
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, _non_list} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Adds a value to a list in the cache with TTL.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key
  - `value` - The value to add
  - `ttl` - The TTL in milliseconds

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  :ok = add_to_list(:killmails, "key", value)
  ```
  """
  @spec add_to_list(cache_type(), cache_key(), cache_value(), pos_integer() | nil) ::
          cache_status()
  def add_to_list(cache_type, key, value, ttl \\ nil) do
    ttl_ms = if ttl, do: ttl * 1000, else: get_ttl(cache_type) * 1000
    namespaced = namespaced_key(cache_type, key)

    case Cachex.transaction(cache_name(cache_type), [namespaced], fn worker ->
           case Cachex.get(worker, namespaced) do
             {:ok, nil} ->
               case Cachex.put(worker, namespaced, [value], ttl: ttl_ms) do
                 {:ok, _} -> :ok
                 error -> error
               end

             {:ok, list} when is_list(list) ->
               case Cachex.put(worker, namespaced, [value | list], ttl: ttl_ms) do
                 {:ok, _} -> :ok
                 error -> error
               end

             _ ->
               case Cachex.put(worker, namespaced, [value], ttl: ttl_ms) do
                 {:ok, _} -> :ok
                 error -> error
               end
           end
         end) do
      {:ok, result} -> result
      error -> error
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
    namespaced = namespaced_key(cache_type, key)

    case Cachex.transaction(cache_name(cache_type), [namespaced], fn worker ->
           case Cachex.get(worker, namespaced) do
             {:ok, nil} ->
               :ok

             {:ok, list} when is_list(list) ->
               case Cachex.put(worker, namespaced, Enum.reject(list, &(&1 == value))) do
                 {:ok, _} -> :ok
                 error -> error
               end

             _ ->
               :ok
           end
         end) do
      {:ok, result} -> result
      error -> error
    end
  end

  @doc """
  Clears all entries from the configured cache.
  """
  @spec clear(atom()) :: cache_status()
  def clear(cache_type) do
    case Cachex.clear(cache_name(cache_type)) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Gets the size of the configured cache.
  """
  @spec size(atom()) :: {:ok, non_neg_integer()} | {:error, term()}
  def size(cache_type) do
    Cachex.size(cache_name(cache_type))
  end

  @doc """
  Gets cache statistics for the configured cache.
  """
  @spec stats(atom()) :: {:ok, map()} | {:error, term()}
  def stats(cache_type) do
    Cachex.stats(cache_name(cache_type))
  end

  @doc """
  Gets a counter value from the cache.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key

  ## Returns
  - `{:ok, count}` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, count} = get_counter(:killmails, "key")
  ```
  """
  @spec get_counter(cache_type(), cache_key()) :: cache_result()
  def get_counter(cache_type, key) do
    case get_value(cache_type, key) do
      {:ok, nil} -> {:ok, 0}
      {:ok, count} when is_integer(count) -> {:ok, count}
      _ -> {:ok, 0}
    end
  end

  @doc """
  Increments a counter in the cache.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key

  ## Returns
  - `{:ok, count}` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, count} = increment_counter(:killmails, "key")
  ```
  """
  @spec increment_counter(cache_type(), cache_key(), pos_integer() | nil) :: cache_status()
  def increment_counter(cache_type, key, ttl \\ nil) do
    ttl_ms = if ttl, do: ttl * 1000, else: get_ttl(cache_type) * 1000
    namespaced = namespaced_key(cache_type, key)

    case Cachex.transaction(cache_name(cache_type), [namespaced], fn worker ->
           case Cachex.get(worker, namespaced) do
             {:ok, nil} ->
               case Cachex.put(worker, namespaced, 1, ttl: ttl_ms) do
                 {:ok, _} -> :ok
                 error -> error
               end

             {:ok, count} when is_integer(count) ->
               case Cachex.put(worker, namespaced, count + 1, ttl: ttl_ms) do
                 {:ok, _} -> :ok
                 error -> error
               end

             _ ->
               case Cachex.put(worker, namespaced, 1, ttl: ttl_ms) do
                 {:ok, _} -> :ok
                 error -> error
               end
           end
         end) do
      {:ok, result} -> result
      error -> error
    end
  end

  @doc """
  Decrements a counter in the cache.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key

  ## Returns
  - `{:ok, count}` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, count} = decrement_counter(:killmails, "key")
  ```
  """
  @spec decrement_counter(cache_type(), cache_key()) :: cache_status()
  def decrement_counter(cache_type, key) do
    namespaced = namespaced_key(cache_type, key)

    case Cachex.transaction(cache_name(cache_type), [namespaced], fn worker ->
           case Cachex.get(worker, namespaced) do
             {:ok, nil} ->
               :ok

             {:ok, count} when is_integer(count) and count > 0 ->
               case Cachex.put(worker, namespaced, count - 1) do
                 {:ok, _} -> :ok
                 error -> error
               end

             _ ->
               :ok
           end
         end) do
      {:ok, result} -> result
      error -> error
    end
  end

  @doc """
  Checks if a key exists in the cache.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key

  ## Returns
  - `{:ok, true}` - If the key exists
  - `{:ok, false}` - If the key does not exist
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, true} = exists?(:killmails, "key")
  {:ok, false} = exists?(:killmails, "non_existent_key")
  ```
  """
  @spec exists?(cache_type(), cache_key()) :: {:ok, boolean()} | {:error, term()}
  def exists?(cache_type, key) do
    case Cachex.exists?(cache_name(cache_type), namespaced_key(cache_type, key)) do
      {:ok, exists} -> {:ok, exists}
      error -> error
    end
  end

  @doc """
  Gets the TTL of a key in the cache.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)
  - `key` - The cache key

  ## Returns
  - `{:ok, ttl}` - On success
  - `{:error, reason}` - On failure

  ## Example

  ```elixir
  {:ok, ttl} = ttl(:killmails, "key")
  ```
  """
  @spec ttl(cache_type(), cache_key()) :: {:ok, pos_integer()} | {:error, term()}
  def ttl(cache_type, key) do
    case Cachex.ttl(cache_name(cache_type), namespaced_key(cache_type, key)) do
      {:ok, ttl} -> {:ok, ttl}
      error -> error
    end
  end

  defp cache_name(_cache_type) do
    # Use unified cache for all cache types
    # The supervisor creates a single :unified_cache instance
    :unified_cache
  end

  # Add helper function to generate namespaced keys for the unified cache
  defp namespaced_key(cache_type, key) do
    "#{cache_type}:#{key}"
  end

  @doc false
  @spec get_ttl(cache_type()) :: pos_integer()
  defp get_ttl(cache_type) do
    case cache_type do
      :killmails -> Config.cache(:killmails, :ttl) || 3600
      :system -> Config.cache(:system, :ttl) || 3600
      :esi -> Config.cache(:esi, :ttl) || 3600
    end
  end
end
