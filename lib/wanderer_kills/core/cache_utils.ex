defmodule WandererKills.Core.CacheUtils do
  @moduledoc """
  Shared cache utility functions for killmail operations.

  This module consolidates common cache operations that were previously
  duplicated across multiple modules.
  """

  require Logger
  alias WandererKills.Cache.{ESI, Systems}

  @doc """
  Caches killmails for a specific system.

  This function:
  1. Updates the system's fetch timestamp
  2. Caches individual killmails by ID
  3. Associates killmail IDs with the system
  4. Adds the system to the active systems list

  ## Parameters
  - `system_id` - The solar system ID
  - `killmails` - List of killmail maps

  ## Returns
  - `:ok` on success
  - `{:error, :cache_exception}` on failure
  """
  @spec cache_killmails_for_system(integer(), [map()]) :: :ok | {:error, term()}
  def cache_killmails_for_system(system_id, killmails) when is_list(killmails) do
    try do
      # Update fetch timestamp
      case Systems.set_fetch_timestamp(system_id, DateTime.utc_now()) do
        {:ok, _} -> :ok
        # Continue anyway
        {:error, _reason} -> :ok
      end

      # Extract killmail IDs and cache individual killmails
      killmail_ids =
        killmails
        |> Enum.map(fn killmail ->
          killmail_id = Map.get(killmail, "killmail_id") || Map.get(killmail, "killID")

          if killmail_id do
            # Cache the individual killmail
            ESI.put_killmail(killmail_id, killmail)
            killmail_id
          else
            nil
          end
        end)
        |> Enum.filter(&(&1 != nil))

      # Add each killmail ID to system's killmail list
      Enum.each(killmail_ids, fn killmail_id ->
        Systems.add_killmail(system_id, killmail_id)
      end)

      # Add system to active list
      Systems.add_active(system_id)

      :ok
    rescue
      _error -> {:error, :cache_exception}
    end
  end
end
