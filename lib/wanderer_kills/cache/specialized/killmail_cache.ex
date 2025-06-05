defmodule WandererKills.Cache.Specialized.KillmailCache do
  @moduledoc """
  Handles caching operations specific to killmails.

  This module uses configuration-driven cache settings instead of hardcoded values.
  """

  require Logger
  alias WandererKills.Cache.Base
  alias WandererKills.Cache.Key
  alias WandererKills.Core.Config

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
  def get_killmail(killmail_id) do
    Base.get_value(:killmails, Key.killmail_key(killmail_id))
  end

  @doc """
  Stores a killmail in the cache using configured TTL.
  """
  @spec set_killmail(integer(), map()) :: cache_status()
  def set_killmail(killmail_id, data) do
    ttl = Config.cache(:killmails, :ttl)
    Base.set_value(:killmails, Key.killmail_key(killmail_id), data, ttl)
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

  def delete_killmail(killmail_id) do
    Base.delete_value(:killmails, Key.killmail_key(killmail_id))
  end

  def get_killmail_ids do
    Base.get_list(:killmails, Key.killmail_ids_key())
  end

  def add_killmail_id(killmail_id) do
    ttl = Config.cache(:killmails, :ttl)
    Base.add_to_list(:killmails, Key.killmail_ids_key(), killmail_id, ttl)
  end

  def remove_killmail_id(killmail_id) do
    Base.remove_from_list(:killmails, Key.killmail_ids_key(), killmail_id)
  end
end
