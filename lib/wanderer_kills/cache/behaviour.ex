defmodule WandererKills.Cache.Behaviour do
  @moduledoc """
  Behavior for cache implementations.
  
  This behavior defines the contract for cache operations that can be
  implemented by different backends (Cachex, ETS, Redis, etc.).
  """

  @type cache_name :: atom()
  @type key :: String.t()
  @type value :: any()
  @type ttl :: pos_integer() | :infinity
  @type cache_result :: {:ok, value()} | {:ok, nil} | {:error, term()}
  @type cache_write_result :: {:ok, boolean()} | {:error, term()}

  @doc """
  Get a value from the cache.
  Returns {:ok, value} if found, {:ok, nil} if not found, {:error, reason} on error.
  """
  @callback get(cache_name(), key()) :: cache_result()

  @doc """
  Put a value in the cache with optional TTL.
  Returns {:ok, true} on success, {:error, reason} on error.
  """
  @callback put(cache_name(), key(), value(), keyword()) :: cache_write_result()

  @doc """
  Delete a value from the cache.
  Returns {:ok, boolean} indicating if the key existed, {:error, reason} on error.
  """
  @callback del(cache_name(), key()) :: cache_write_result()

  @doc """
  Check if a key exists in the cache.
  Returns {:ok, boolean}, {:error, reason} on error.
  """
  @callback exists?(cache_name(), key()) :: {:ok, boolean()} | {:error, term()}

  @doc """
  Clear all entries from the cache.
  Returns {:ok, count} where count is number of cleared entries, {:error, reason} on error.
  """
  @callback clear(cache_name()) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Get cache size (number of entries).
  Returns {:ok, size}, {:error, reason} on error.
  """
  @callback size(cache_name()) :: {:ok, non_neg_integer()} | {:error, term()}
end