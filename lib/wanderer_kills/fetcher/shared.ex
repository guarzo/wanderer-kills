defmodule WandererKills.Fetcher do
  @moduledoc """
  ⚠️  DEPRECATED: This module has been refactored into separate services.

  This module now acts as a thin wrapper around the new refactored fetcher architecture:
  - `WandererKills.Fetcher.Coordinator` - Main orchestration
  - `WandererKills.Fetcher.ZkbService` - ZKB API interactions
  - `WandererKills.Fetcher.CacheService` - Cache operations
  - `WandererKills.Fetcher.Processor` - Killmail processing

  ## Migration Guide

  Please update your code to use the new modules directly:

  ```elixir
  # Before:
  {:ok, killmail} = WandererKills.Fetcher.fetch_and_cache_killmail(12345)

  # After:
  {:ok, killmail} = WandererKills.Fetcher.Coordinator.fetch_and_cache_killmail(12345)
  ```

  ## Legacy Support

  This module will continue to work as before by delegating to the new architecture,
  but it may be removed in a future version.
  """

  alias WandererKills.Fetcher.Coordinator

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type killmail :: map()
  @type fetch_opts :: [
          limit: pos_integer(),
          force: boolean(),
          since_hours: pos_integer(),
          max_concurrency: pos_integer(),
          timeout: pos_integer()
        ]

  # =============================================================================
  # Delegated Functions (for backward compatibility)
  # =============================================================================

  @doc """
  Fetches a killmail from zKillboard and caches it.

  ⚠️  DEPRECATED: Use `WandererKills.Fetcher.Coordinator.fetch_and_cache_killmail/2` instead.
  """
  @deprecated "Use WandererKills.Fetcher.Coordinator.fetch_and_cache_killmail/2"
  @spec fetch_and_cache_killmail(killmail_id(), module() | nil) ::
          {:ok, killmail()} | {:error, term()}
  def fetch_and_cache_killmail(killmail_id, client \\ nil) do
    Coordinator.fetch_and_cache_killmail(killmail_id, client)
  end

  @doc """
  Fetch and parse killmails for a given system.

  ⚠️  DEPRECATED: Use `WandererKills.Fetcher.Coordinator.fetch_killmails_for_system/2` instead.
  """
  @deprecated "Use WandererKills.Fetcher.Coordinator.fetch_killmails_for_system/2"
  @spec fetch_killmails_for_system(String.t() | integer(), fetch_opts()) ::
          {:ok, [killmail()]} | {:error, term()}
  def fetch_killmails_for_system(system_id, opts \\ []) do
    Coordinator.fetch_killmails_for_system(system_id, opts)
  end

  @doc """
  Fetch killmails for multiple systems in parallel.

  ⚠️  DEPRECATED: Use `WandererKills.Fetcher.Coordinator.fetch_killmails_for_systems/2` instead.
  """
  @deprecated "Use WandererKills.Fetcher.Coordinator.fetch_killmails_for_systems/2"
  @spec fetch_killmails_for_systems([system_id()], fetch_opts()) ::
          %{system_id() => {:ok, [killmail()]} | {:error, term()}} | {:error, term()}
  def fetch_killmails_for_systems(system_ids, opts \\ []) do
    Coordinator.fetch_killmails_for_systems(system_ids, opts)
  end

  @doc """
  Get the kill count for a system from zKillboard stats.

  ⚠️  DEPRECATED: Use `WandererKills.Fetcher.Coordinator.get_system_kill_count/2` instead.
  """
  @deprecated "Use WandererKills.Fetcher.Coordinator.get_system_kill_count/2"
  @spec get_system_kill_count(String.t() | integer(), module() | nil) ::
          {:ok, integer()} | {:error, term()}
  def get_system_kill_count(system_id, client \\ nil) do
    Coordinator.get_system_kill_count(system_id, client)
  end

  # =============================================================================
  # Legacy Internal Functions (deprecated)
  # =============================================================================

  @doc """
  Legacy internal implementation for backward compatibility.

  ⚠️  DEPRECATED: This function is kept for compatibility but should not be used directly.
  """
  @deprecated "Internal function, use Coordinator module instead"
  def fetch_killmails_for_system(system_id, _source, opts, _client) do
    # Ignore source and client parameters, delegate to new coordinator
    Coordinator.fetch_killmails_for_system(system_id, opts)
  end
end
