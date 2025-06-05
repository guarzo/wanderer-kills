defmodule WandererKills.Zkb.ClientBehaviour do
  @moduledoc """
  Behaviour for zKillboard API client.
  """

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type corporation_id :: pos_integer()
  @type alliance_id :: pos_integer()
  @type character_id :: pos_integer()
  @type killmail :: map()

  @callback fetch_killmail(killmail_id()) :: {:ok, killmail()} | {:error, term()}
  @callback fetch_system_killmails(system_id()) :: {:ok, [killmail()]} | {:error, term()}
  @callback get_corporation_killmails(corporation_id()) :: {:ok, [killmail()]} | {:error, term()}
  @callback get_alliance_killmails(alliance_id()) :: {:ok, [killmail()]} | {:error, term()}
  @callback get_character_killmails(character_id()) :: {:ok, [killmail()]} | {:error, term()}
  @callback fetch_system_killmails_esi(system_id()) :: {:ok, [killmail()]} | {:error, term()}
  @callback enrich_killmail(killmail()) :: {:ok, killmail()} | {:error, term()}
  @callback get_system_kill_count(system_id()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback fetch_active_systems() :: {:ok, [system_id()]} | {:error, term()}
  @callback build_query_params(keyword()) :: keyword()
  @callback base_url() :: String.t()
end
