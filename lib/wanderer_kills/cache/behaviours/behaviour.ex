defmodule WandererKills.Cache.Behaviour do
  @moduledoc """
  Behaviour defining common cache operations.

  This behaviour extracts shared functionality that's duplicated across
  cache modules (KillmailCache, SystemCache, Esi.Cache).
  """

  @type cache_result :: {:ok, term()} | {:error, term()}
  @type cache_status :: :ok | {:error, term()}

  @doc """
  Gets a value from the cache.
  """
  @callback get_value(term()) :: cache_result()

  @doc """
  Sets a value in the cache with TTL.
  """
  @callback set_value(term(), term(), non_neg_integer()) :: cache_status()

  @doc """
  Sets a value in the cache using default TTL.
  """
  @callback set_value(term(), term()) :: cache_status()

  @doc """
  Deletes a value from the cache.
  """
  @callback delete_value(term()) :: cache_status()

  @doc """
  Clears all entries from the cache.
  """
  @callback clear() :: cache_status()

  @doc """
  Adds an item to a list in the cache.
  """
  @callback add_to_list(term(), term()) :: cache_status()

  @doc """
  Removes an item from a list in the cache.
  """
  @callback remove_from_list(term(), term()) :: cache_status()

  @doc """
  Gets a list from the cache, returning empty list if not found.
  """
  @callback get_list(term()) :: {:ok, list()} | {:error, term()}
end
