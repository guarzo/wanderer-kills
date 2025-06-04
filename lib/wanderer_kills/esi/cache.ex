defmodule WandererKills.Esi.Cache do
  @moduledoc """
  Backward compatibility alias for ESI cache operations.

  This module provides backward compatibility for code that references
  WandererKills.Esi.Cache by delegating to the actual implementation
  at WandererKills.Cache.Specialized.EsiCache.
  """

  alias WandererKills.Cache.Specialized.EsiCache

  # Delegate all functions to the specialized ESI cache
  defdelegate get_character_info(character_id), to: EsiCache
  defdelegate get_corporation_info(corporation_id), to: EsiCache
  defdelegate get_alliance_info(alliance_id), to: EsiCache
  defdelegate get_system_info(system_id), to: EsiCache
  defdelegate get_type_info(type_id), to: EsiCache
  defdelegate get_group_info(group_id), to: EsiCache
  defdelegate get_killmail(killmail_id, hash), to: EsiCache
  defdelegate clear(), to: EsiCache
end
