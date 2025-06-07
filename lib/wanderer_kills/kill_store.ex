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
  @killmail_events_table :killmail_events
  @client_offsets_table :client_offsets
  @counters_table :counters
  @killmails_table :killmails

  @type kill_id :: integer()
  @type system_id :: integer()
  @type client_id :: term()
  @type event_id :: integer()
  @type kill_data :: map()
  @type client_offsets :: %{system_id() => event_id()}

  @doc """
  Initializes all required ETS tables at application start.

  This should be called from Application.start/2 before starting the supervision tree.
  """
  @spec init_tables!() :: :ok
  def init_tables! do
    # Main killmail storage table
    :ets.new(@killmails_table, [:set, :named_table, :public, {:read_concurrency, true}])

    # Event storage for streaming killmails
    :ets.new(@killmail_events_table, [
      :ordered_set,
      :named_table,
      :public,
      {:read_concurrency, true}
    ])

    # Client offset tracking for event streaming
    :ets.new(@client_offsets_table, [:set, :named_table, :public, {:read_concurrency, true}])

    # Counters for event IDs and statistics
    :ets.new(@counters_table, [:set, :named_table, :public, {:read_concurrency, true}])

    # Initialize event counter
    :ets.insert(@counters_table, {:event_counter, 0})

    Logger.info(
      "Initialized KillStore ETS tables: #{inspect([@killmails_table, @killmail_events_table, @client_offsets_table, @counters_table])}"
    )

    :ok
  end

  @doc """
  Stores a killmail in the store.
  """
  @spec put(kill_id(), kill_data()) :: :ok
  def put(kill_id, kill_data) when is_integer(kill_id) and is_map(kill_data) do
    :ets.insert(@killmails_table, {kill_id, kill_data})
    :ok
  end

  @doc """
  Retrieves a killmail by ID.
  """
  @spec get(kill_id()) :: {:ok, kill_data()} | {:error, :not_found}
  def get(kill_id) when is_integer(kill_id) do
    case :ets.lookup(@killmails_table, kill_id) do
      [{^kill_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all killmails for a specific system.
  """
  @spec list_by_system(system_id()) :: [kill_data()]
  def list_by_system(system_id) when is_integer(system_id) do
    # Use match spec to find all killmails for the system
    # Match pattern: {kill_id, %{"solar_system_id" => system_id, ...}}
    ms = [
      {{:"$1", %{"solar_system_id" => system_id}}, [], [:"$2"]},
      {{:"$1", %{solar_system_id: system_id}}, [], [:"$2"]}
    ]

    :ets.select(@killmails_table, ms)
  end

  @doc """
  Deletes a killmail from the store.
  """
  @spec delete(kill_id()) :: :ok
  def delete(kill_id) when is_integer(kill_id) do
    :ets.delete(@killmails_table, kill_id)
    :ok
  end

  @doc """
  Inserts an event for streaming functionality.
  """
  @spec insert_event(system_id(), kill_data()) :: :ok
  def insert_event(system_id, kill_data) when is_integer(system_id) and is_map(kill_data) do
    event_id = get_next_event_id()
    :ets.insert(@killmail_events_table, {event_id, system_id, kill_data})
    :ok
  end

  @doc """
  Gets client offsets for event streaming.
  """
  @spec get_client_offsets(client_id()) :: client_offsets()
  def get_client_offsets(client_id) do
    case :ets.lookup(@client_offsets_table, client_id) do
      [{^client_id, offsets}] when is_map(offsets) -> offsets
      [] -> %{}
    end
  end

  @doc """
  Updates client offsets for event streaming.
  """
  @spec put_client_offsets(client_id(), client_offsets()) :: :ok
  def put_client_offsets(client_id, offsets) when is_map(offsets) do
    :ets.insert(@client_offsets_table, {client_id, offsets})
    :ok
  end

  @doc """
  Fetches events for a client from specific systems since their last offset.
  """
  @spec fetch_events(client_id(), [system_id()], non_neg_integer()) :: [kill_data()]
  def fetch_events(client_id, system_ids, limit \\ 100)
      when is_list(system_ids) and is_integer(limit) do
    client_offsets = get_client_offsets(client_id)

    # Build match specs for each system to get events after the client's offset
    match_specs =
      Enum.flat_map(system_ids, fn sys_id ->
        offset = Map.get(client_offsets, sys_id, 0)
        [{{:"$1", sys_id, :"$2"}, [{:>, :"$1", offset}], [:"$2"]}]
      end)

    events = :ets.select(@killmail_events_table, match_specs)

    # Take only the requested limit and sort by event ID
    events
    |> Enum.take(limit)
    |> Enum.sort()
  end

  @doc """
  Clears all data from all tables (for testing).
  """
  @spec clear_all() :: :ok
  def clear_all do
    :ets.delete_all_objects(@killmails_table)
    :ets.delete_all_objects(@killmail_events_table)
    :ets.delete_all_objects(@client_offsets_table)
    :ets.delete_all_objects(@counters_table)
    # Reinitialize event counter
    :ets.insert(@counters_table, {:event_counter, 0})
    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec get_next_event_id() :: event_id()
  defp get_next_event_id do
    :ets.update_counter(@counters_table, :event_counter, 1)
  end
end
