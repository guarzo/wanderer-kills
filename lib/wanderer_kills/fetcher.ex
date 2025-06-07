defmodule WandererKills.Fetching.API do
  @moduledoc """
  Public API for the WandererKills Fetcher domain.

  This module provides a unified interface to fetching operations including:
  - Killmail fetching from various sources
  - Active systems fetching
  - Batch operations
  - Shared fetching utilities

  ## Usage

  ```elixir
  # Instead of: alias WandererKills.Fetching.KillmailFetcher
  alias WandererKills.Fetching.API, as: Fetcher

  {:ok, killmail} = Fetcher.fetch_killmail(123456)
  ```

  This provides a stable interface for fetching operations across the application.
  """

  # Fetcher modules
  alias WandererKills.External.ZKB.Fetcher, as: KillmailFetcher
  alias WandererKills.Systems.Fetcher, as: ActiveSystemsFetcher

  #
  # Killmail Fetching API
  #

  @doc """
  Fetches a single killmail by ID and stores it.
  """
  @spec fetch_killmail(integer(), module() | nil) :: {:ok, map()} | {:error, term()}
  def fetch_killmail(killmail_id, client \\ nil) do
    KillmailFetcher.fetch_killmail(killmail_id, client)
  end

  @doc """
  Fetches all killmails for a system and stores them.
  """
  @spec fetch_system_killmails(integer(), module() | nil) :: {:ok, [map()]} | {:error, term()}
  def fetch_system_killmails(system_id, client \\ nil) do
    KillmailFetcher.fetch_system_killmails(system_id, client)
  end

  #
  # Active Systems API
  #

  @doc """
  Fetches and updates active systems.
  """
  @spec fetch_active_systems() :: :ok | {:error, term()}
  def fetch_active_systems do
    case ActiveSystemsFetcher.fetch_active_systems() do
      {:ok, _systems} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  #
  # Batch Operations API
  #

  @doc """
  Fetches multiple killmails in parallel.
  """
  @spec fetch_killmails_batch([integer()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def fetch_killmails_batch(_killmail_ids, _opts \\ []) do
    # For now, use the batch processor to handle parallel killmail fetching
    # This would need to be implemented based on available functions
    {:error, :not_implemented}
  end

  @doc """
  Fetches killmails for multiple systems in parallel.
  """
  @spec fetch_systems_batch([integer()], keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_systems_batch(system_ids, opts \\ []) do
    # Use the new Coordinator's batch function directly
    results = WandererKills.Fetching.Coordinator.fetch_killmails_for_systems(system_ids, opts)
    {:ok, results}
  end

  #
  # Shared Utilities API
  #

  @doc """
  Gets killmails for a system using the shared fetcher.
  """
  @spec get_fresh_system_killmails(integer()) :: {:ok, [map()]} | {:error, term()}
  def get_fresh_system_killmails(system_id) do
    WandererKills.Fetching.Coordinator.fetch_killmails_for_system(system_id)
  end

  @doc """
  Gets system kill count from zKillboard.
  """
  @spec get_system_kill_count(integer()) :: {:ok, integer()} | {:error, term()}
  def get_system_kill_count(system_id) do
    WandererKills.Fetching.Coordinator.get_system_kill_count(system_id)
  end

  #
  # Type Definitions
  #

  @type killmail :: map()
  @type system_id :: integer()
  @type killmail_id :: integer()
  @type fetch_opts :: keyword()
  @type result(t) :: {:ok, t} | {:error, term()}
end
