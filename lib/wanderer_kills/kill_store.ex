defmodule WandererKills.KillStore do
  @moduledoc """
  Simplified ETS-backed killmail storage with pattern-matching query support.

  This module provides a clean API over ETS tables for storing and querying
  killmails. ETS is used here specifically because we need efficient pattern
  matching queries like "give me all kills for system X".

  The module exposes only the core operations needed for killmail storage
  without the complexity of a GenServer.
  """

  require Logger

  # ETS tables for killmail storage
  @killmail_table :killmails
  @system_killmails_table :system_killmails
  @system_fetch_timestamps_table :system_fetch_timestamps

  @type kill_id :: integer()
  @type system_id :: integer()
  @type kill_data :: map()

  @doc """
  Initializes all required ETS tables at application start.

  This should be called from Application.start/2 before starting the supervision tree.
  """
  @spec init_tables!() :: :ok
  def init_tables! do
    # Main killmail storage table
    :ets.new(@killmail_table, [:set, :named_table, :public, {:read_concurrency, true}])

    # System-specific killmail lists
    :ets.new(@system_killmails_table, [:set, :named_table, :public, {:read_concurrency, true}])

    # System fetch timestamps
    :ets.new(@system_fetch_timestamps_table, [
      :set,
      :named_table,
      :public,
      {:read_concurrency, true}
    ])

    Logger.info(
      "Initialized KillStore ETS tables: #{inspect([@killmail_table, @system_killmails_table, @system_fetch_timestamps_table])}"
    )

    :ok
  end

  # ============================================================================
  # Core Killmail Storage API
  # ============================================================================

  @doc """
  Stores a killmail in the store.
  """
  @spec put(kill_id(), system_id(), kill_data()) :: :ok
  def put(kill_id, system_id, kill_data)
      when is_integer(kill_id) and is_integer(system_id) and is_map(kill_data) do
    :ets.insert(@killmail_table, {kill_id, kill_data})

    # Associate with system
    case :ets.lookup(@system_killmails_table, system_id) do
      [] ->
        :ets.insert(@system_killmails_table, {system_id, [kill_id]})

      [{^system_id, existing_ids}] ->
        # Ensure we don't add duplicates
        if kill_id not in existing_ids do
          :ets.insert(@system_killmails_table, {system_id, [kill_id | existing_ids]})
        end
    end

    :ok
  end

  @doc """
  Retrieves a killmail by ID.
  """
  @spec get(kill_id()) :: {:ok, kill_data()} | :error
  def get(kill_id) when is_integer(kill_id) do
    case :ets.lookup(@killmail_table, kill_id) do
      [{^kill_id, data}] -> {:ok, data}
      [] -> :error
    end
  end

  @doc """
  Lists all killmails for a specific system.
  """
  @spec list_by_system(system_id()) :: [kill_data()]
  def list_by_system(system_id) when is_integer(system_id) do
    case :ets.lookup(@system_killmails_table, system_id) do
      [{^system_id, killmail_ids}] ->
        # Retrieve the actual killmail data for each ID
        Enum.flat_map(killmail_ids, fn killmail_id ->
          case :ets.lookup(@killmail_table, killmail_id) do
            [{^killmail_id, killmail_data}] -> [killmail_data]
            [] -> []
          end
        end)

      [] ->
        []
    end
  end

  @doc """
  Deletes a killmail from the store.
  """
  @spec delete(kill_id()) :: :ok
  def delete(kill_id) when is_integer(kill_id) do
    :ets.delete(@killmail_table, kill_id)

    # Remove from system associations
    # We need to search through all systems to find and remove this killmail_id
    :ets.foldl(
      fn {system_id, killmail_ids}, _acc ->
        if kill_id in killmail_ids do
          updated_ids = List.delete(killmail_ids, kill_id)
          :ets.insert(@system_killmails_table, {system_id, updated_ids})
        end

        :ok
      end,
      :ok,
      @system_killmails_table
    )

    :ok
  end

  # ============================================================================
  # System Fetch Timestamp Management
  # ============================================================================

  @doc """
  Sets the fetch timestamp for a system.
  """
  @spec fetch_timestamp(system_id(), DateTime.t()) :: :ok
  def fetch_timestamp(system_id, timestamp) when is_integer(system_id) do
    :ets.insert(@system_fetch_timestamps_table, {system_id, timestamp})
    :ok
  end

  @doc """
  Gets the fetch timestamp for a system.
  """
  @spec fetch_timestamp(system_id()) :: {:ok, DateTime.t()} | :error
  def fetch_timestamp(system_id) when is_integer(system_id) do
    case :ets.lookup(@system_fetch_timestamps_table, system_id) do
      [{^system_id, timestamp}] -> {:ok, timestamp}
      [] -> :error
    end
  end

  # ============================================================================
  # Testing Support
  # ============================================================================

  @doc """
  Clears all data from all tables (for testing).
  """
  @spec cleanup_tables() :: :ok
  def cleanup_tables do
    :ets.delete_all_objects(@killmail_table)
    :ets.delete_all_objects(@system_killmails_table)
    :ets.delete_all_objects(@system_fetch_timestamps_table)
    :ok
  end

  @doc """
  Clears all data from all tables (alias for cleanup_tables).
  """
  @spec clear() :: :ok
  def clear, do: cleanup_tables()
end
