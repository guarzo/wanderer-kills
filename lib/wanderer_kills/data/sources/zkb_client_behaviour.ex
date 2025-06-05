defmodule WandererKills.Data.Sources.ZkbClientBehaviour do
  @moduledoc """
  Behaviour for zKillboard API client.
  """

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type killmail :: map()

  @callback fetch_killmail(killmail_id()) :: {:ok, killmail()} | {:error, term()}
  @callback fetch_system_killmails(system_id()) :: {:ok, [killmail()]} | {:error, term()}
  @callback fetch_system_killmails_esi(system_id()) :: {:ok, [killmail()]} | {:error, term()}
  @callback enrich_killmail(killmail()) :: {:ok, killmail()} | {:error, term()}
  @callback get_system_kill_count(system_id()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback fetch_system_kill_count(system_id()) :: {:ok, integer()} | {:error, term()}
end
