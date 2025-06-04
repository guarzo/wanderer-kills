defmodule WandererKills.Cache.Specialized.KillmailCache do
  @moduledoc """
  Handles caching operations specific to killmails.

  This module uses configuration-driven cache settings instead of hardcoded values.
  """

  require Logger
  alias WandererKills.Cache.Base
  alias WandererKills.Cache.Key

  @type cache_result :: {:ok, term()} | {:error, term()}
  @type cache_status :: :ok | {:error, term()}

  @doc """
  Gets a value from the killmails cache.
  """
  @spec get_value(term()) :: cache_result()
  def get_value(key), do: Base.get_value(:killmails, key)

  @doc """
  Sets a value in the killmails cache with TTL.
  """
  @spec set_value(term(), term(), non_neg_integer()) :: cache_status()
  def set_value(key, value, ttl),
    do: Base.set_value(:killmails, key, value, ttl)

  @doc """
  Gets a killmail from the cache.
  """
  @spec get_killmail(integer()) :: cache_result()
  def get_killmail(id) do
    Base.get_value(:killmails, Key.killmail_key(id))
  end

  @doc """
  Stores a killmail in the cache using configured TTL.
  """
  @spec set_killmail(integer(), map()) :: cache_status()
  def set_killmail(id, killmail) do
    Base.set_value(:killmails, Key.killmail_key(id), killmail)
  end

  @doc """
  Deletes a key from the killmails cache.
  """
  @spec delete_value(term()) :: cache_status()
  def delete_value(key), do: Base.delete_value(:killmails, key)

  @doc """
  Clears all entries from the killmails cache.
  """
  @spec clear() :: cache_status()
  def clear(), do: Base.clear(:killmails)
end
