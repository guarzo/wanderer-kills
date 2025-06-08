defmodule WandererKills.Cache.KillmailCache do
  @moduledoc """
  Killmail-specific cache operations for WandererKills.
  """

  alias WandererKills.Cache.Helper

  @doc """
  Get a killmail from cache.
  """
  def get(id), do: Helper.get_with_error("killmails", to_string(id))

  @doc """
  Put a killmail in cache.
  """
  def put(id, data), do: Helper.put("killmails", to_string(id), data)

  @doc """
  Get or set a killmail using a fallback function.
  """
  def get_or_set(id, fallback_fn), do: Helper.get_or_set("killmails", to_string(id), fallback_fn)

  @doc """
  Delete a killmail from cache.
  """
  def delete(id), do: Helper.delete("killmails", to_string(id))
end
