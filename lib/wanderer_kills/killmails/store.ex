defmodule WandererKills.Killmails.Store do
  @moduledoc """
  Backward compatibility alias for KillmailStore.

  This module has been moved to WandererKills.Data.Stores.KillmailStore
  to better organize the codebase structure.
  """

  alias WandererKills.Data.Stores.KillmailStore

  # Delegate all functions to the new location
  defdelegate start_link(opts), to: KillmailStore
  defdelegate insert_event(system_id, killmail), to: KillmailStore
  defdelegate fetch_for_client(client_id, system_ids), to: KillmailStore
  defdelegate fetch_one_event(client_id, system_ids), to: KillmailStore
  defdelegate get_killmail(killmail_id), to: KillmailStore
  defdelegate get_killmails_for_system(system_id), to: KillmailStore
  defdelegate child_spec(opts), to: KillmailStore
  defdelegate cleanup_tables(), to: KillmailStore
  defdelegate store_killmail(killmail), to: KillmailStore
  defdelegate delete_killmail(killmail_id), to: KillmailStore
  defdelegate add_system_killmail(system_id, killmail_id), to: KillmailStore
  defdelegate remove_system_killmail(system_id, killmail_id), to: KillmailStore
  defdelegate increment_system_kill_count(system_id), to: KillmailStore
  defdelegate get_system_kill_count(system_id), to: KillmailStore
  defdelegate set_system_fetch_timestamp(system_id, timestamp), to: KillmailStore
  defdelegate get_system_fetch_timestamp(system_id), to: KillmailStore
end
