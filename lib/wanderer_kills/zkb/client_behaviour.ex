defmodule WandererKills.Zkb.ClientBehaviour do
  @moduledoc """
  Behaviour for ZKB (zKillboard) client implementations.
  """

  @doc """
  Fetches a killmail from zKillboard.
  """
  @callback fetch_killmail(integer()) :: {:ok, map()} | {:error, term()}

  @doc """
  Fetches killmails for a system from zKillboard.
  """
  @callback fetch_system_killmails(integer()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Gets the kill count for a system.
  """
  @callback get_system_kill_count(integer()) :: {:ok, integer()} | {:error, term()}
end
