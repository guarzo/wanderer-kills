defmodule WandererKills.Parser.CacheHandler do
  @moduledoc """
  Handles caching of killmails.
  """

  require Logger
  alias WandererKills.Cache

  @type killmail :: map()
  @type result :: {:ok, killmail()} | {:error, term()}

  @doc """
  Stores a killmail in the cache.
  """
  @spec store_killmail(map()) :: :ok | {:error, term()}
  def store_killmail(killmail) when is_map(killmail) do
    id = get_killmail_id(killmail)
    sys_id = get_system_id(killmail)

    case Cache.set_killmail(id, killmail) do
      :ok ->
        Logger.debug("Stored killmail in cache",
          killmail_id: id,
          operation: :cache_store,
          status: :success
        )

        # Add to system killmail list if system ID is available
        if sys_id do
          Cache.add_system_killmail(sys_id, id)
        end

        :ok
    end
  end

  defp get_killmail_id(killmail) do
    killmail["killmail_id"] || killmail["killID"]
  end

  defp get_system_id(killmail) do
    killmail["solar_system_id"] || killmail["solarSystemID"]
  end

  @doc """
  Increments the kill count for a system.

  This function extracts the system ID from a killmail and increments
  the kill count for that system. This consolidates the previously
  duplicated update_kill_count/1 and increment_kill_count/1 functions.
  """
  @spec increment_kill_count(map()) :: :ok
  def increment_kill_count(killmail) when is_map(killmail) do
    case get_system_id(killmail) do
      nil ->
        Logger.warning("Cannot increment kill count - no system ID found in killmail")
        :ok

      sys_id ->
        Cache.increment_system_kill_count(sys_id)

        Logger.debug("Incremented kill count for system",
          system_id: sys_id,
          operation: :increment_kill_count,
          status: :success
        )

        :ok
    end
  end

  # Deprecated: Use increment_kill_count/1 instead
  @deprecated "Use increment_kill_count/1 instead"
  @spec update_kill_count(map()) :: :ok
  def update_kill_count(killmail), do: increment_kill_count(killmail)
end
