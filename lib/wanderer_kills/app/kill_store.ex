defmodule WandererKills.App.KillStore do
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
  @system_killmails_table :system_killmails
  @system_kill_counts_table :system_kill_counts
  @system_fetch_timestamps_table :system_fetch_timestamps

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

    # System-specific killmail lists
    :ets.new(@system_killmails_table, [:set, :named_table, :public, {:read_concurrency, true}])

    # System kill counts
    :ets.new(@system_kill_counts_table, [:set, :named_table, :public, {:read_concurrency, true}])

    # System fetch timestamps
    :ets.new(@system_fetch_timestamps_table, [
      :set,
      :named_table,
      :public,
      {:read_concurrency, true}
    ])

    # Initialize counters
    :ets.insert(@counters_table, {:event_counter, 0})
    :ets.insert(@counters_table, {:killmail_seq, 0})

    Logger.info(
      "Initialized KillStore ETS tables: #{inspect([@killmails_table, @killmail_events_table, @client_offsets_table, @counters_table, @system_killmails_table, @system_kill_counts_table, @system_fetch_timestamps_table])}"
    )

    :ok
  end

  # ============================================================================
  # Core Killmail Storage API
  # ============================================================================

  @doc """
  Stores a killmail in the store.
  """
  @spec put(kill_id(), kill_data()) :: :ok
  def put(kill_id, kill_data) when is_integer(kill_id) and is_map(kill_data) do
    :ets.insert(@killmails_table, {kill_id, kill_data})
    :ok
  end

  @doc """
  Stores a killmail in the store with system association.
  """
  @spec put(kill_id(), system_id(), kill_data()) :: :ok
  def put(kill_id, system_id, kill_data)
      when is_integer(kill_id) and is_integer(system_id) and is_map(kill_data) do
    # Store the killmail
    :ets.insert(@killmails_table, {kill_id, kill_data})

    # Add to system killmails
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
    case :ets.lookup(@killmails_table, kill_id) do
      [{^kill_id, data}] -> {:ok, data}
      [] -> :error
    end
  end

  @doc """
  Lists all killmails for a specific system.
  """
  @spec list_by_system(system_id()) :: [kill_data()]
  def list_by_system(system_id) when is_integer(system_id) do
    # Get all killmail IDs for the system from the system_killmails table
    case :ets.lookup(@system_killmails_table, system_id) do
      [{^system_id, killmail_ids}] ->
        # Retrieve the actual killmail data for each ID
        Enum.flat_map(killmail_ids, &get_killmail_data/1)

      [] ->
        []
    end
  end

  defp get_killmail_data(killmail_id) do
    case :ets.lookup(@killmails_table, killmail_id) do
      [{^killmail_id, killmail_data}] -> [killmail_data]
      [] -> []
    end
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
  Clears all data for testing (alias method).
  """
  @spec clear() :: :ok
  def clear, do: clear_all()

  # ============================================================================
  # Event Streaming API
  # ============================================================================

  @doc """
  Inserts a new killmail event for the given system.

  This function:
  1. Generates a sequential event ID
  2. Stores the killmail data
  3. Associates it with the system
  4. Creates an event for streaming
  5. Broadcasts via PubSub (optional)
  """
  @spec insert_event(system_id(), kill_data()) :: :ok
  def insert_event(system_id, killmail_map) when is_integer(system_id) and is_map(killmail_map) do
    # Get next event ID
    event_id = get_next_event_id()

    # Store the killmail
    killmail_id = killmail_map["killmail_id"]
    :ets.insert(@killmails_table, {killmail_id, killmail_map})

    # Add to system killmails
    case :ets.lookup(@system_killmails_table, system_id) do
      [] ->
        :ets.insert(@system_killmails_table, {system_id, [killmail_id]})

      [{^system_id, existing_ids}] ->
        # Ensure we don't add duplicates
        if killmail_id not in existing_ids do
          :ets.insert(@system_killmails_table, {system_id, [killmail_id | existing_ids]})
        end
    end

    # Insert event for streaming
    :ets.insert(@killmail_events_table, {event_id, system_id, killmail_map})

    # Broadcast via PubSub
    Phoenix.PubSub.broadcast(
      WandererKills.PubSub,
      "system:#{system_id}",
      {:new_killmail, system_id, killmail_map}
    )

    :ok
  end

  @doc """
  Fetches all new events for a client across multiple systems.
  """
  @spec fetch_for_client(client_id(), [system_id()]) ::
          {:ok, [{event_id(), system_id(), kill_data()}]}
  def fetch_for_client(client_id, system_ids) when is_list(system_ids) do
    # Get client offsets
    client_offsets = get_client_offsets(client_id)

    # Handle empty system list
    if Enum.empty?(system_ids) do
      {:ok, []}
    else
      # Create conditions for each system
      conditions =
        Enum.map(system_ids, fn sys_id ->
          {:andalso, {:==, :"$2", sys_id},
           {:>, :"$1", get_offset_for_system(sys_id, client_offsets)}}
        end)

      # Build the match specification guard
      guard =
        case conditions do
          [single] -> single
          multiple -> List.to_tuple([:orelse | multiple])
        end

      # Create match specification for :ets.select
      match_spec = [
        {
          {:"$1", :"$2", :"$3"},
          [guard],
          [{{:"$1", :"$2", :"$3"}}]
        }
      ]

      # Get all matching events
      events = :ets.select(@killmail_events_table, match_spec)

      # Sort by event_id ascending
      sorted_events = Enum.sort_by(events, &elem(&1, 0))

      # Update client offsets for each system
      updated_offsets = update_client_offsets(sorted_events, client_offsets)

      # Store updated offsets
      :ets.insert(@client_offsets_table, {client_id, updated_offsets})

      {:ok, sorted_events}
    end
  end

  @doc """
  Fetches the next single event for a client across multiple systems.
  """
  @spec fetch_one_event(client_id(), [system_id()]) ::
          {:ok, {event_id(), system_id(), kill_data()}} | :empty
  def fetch_one_event(client_id, system_ids) when is_list(system_ids) do
    # Get client offsets
    client_offsets = get_client_offsets(client_id)

    # Handle empty system list
    if Enum.empty?(system_ids) do
      :empty
    else
      # Create conditions for each system
      conditions =
        Enum.map(system_ids, fn sys_id ->
          {:andalso, {:==, :"$2", sys_id},
           {:>, :"$1", get_offset_for_system(sys_id, client_offsets)}}
        end)

      # Build the match specification guard
      guard =
        case conditions do
          [single] -> single
          multiple -> List.to_tuple([:orelse | multiple])
        end

      # Create match specification for :ets.select
      match_spec = [
        {
          {:"$1", :"$2", :"$3"},
          [guard],
          [{{:"$1", :"$2", :"$3"}}]
        }
      ]

      # Use :ets.select to get matching events
      case :ets.select(@killmail_events_table, match_spec, 1) do
        {[{event_id, sys_id, km}], _continuation} ->
          # Update offset for this system only
          updated_offsets = Map.put(client_offsets, sys_id, event_id)
          :ets.insert(@client_offsets_table, {client_id, updated_offsets})

          {:ok, {event_id, sys_id, km}}

        {[], _continuation} ->
          :empty

        :"$end_of_table" ->
          :empty
      end
    end
  end

  # Support single system_id as well as list
  @spec fetch_one_event(client_id(), system_id() | [system_id()]) ::
          {:ok, {event_id(), system_id(), kill_data()}} | :empty
  def fetch_one_event(client_id, system_id) when is_integer(system_id) do
    fetch_one_event(client_id, [system_id])
  end

  @doc """
  Fetches events for a client from specific systems since their last offset.
  Legacy function for compatibility with existing tests.
  """
  @spec fetch_events(client_id(), [system_id()], non_neg_integer()) :: [kill_data()]
  def fetch_events(client_id, system_ids, limit \\ 100)
      when is_list(system_ids) and is_integer(limit) do
    case fetch_for_client(client_id, system_ids) do
      {:ok, events} ->
        # Return only the killmail data, not the tuple
        events
        |> Enum.take(limit)
        |> Enum.map(&elem(&1, 2))
    end
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

  # ============================================================================
  # System-Specific Operations API (from old GenServer)
  # ============================================================================

  @doc """
  Stores a killmail in the store.
  """
  @spec store_killmail(kill_data()) :: :ok | {:error, term()}
  def store_killmail(killmail) when is_map(killmail) do
    killmail_id = killmail["killmail_id"]

    if killmail_id do
      :ets.insert(@killmails_table, {killmail_id, killmail})
      :ok
    else
      {:error, "Killmail missing required killmail_id field"}
    end
  end

  def store_killmail(_invalid) do
    {:error, "Invalid killmail format - must be a map"}
  end

  @doc """
  Retrieves a killmail by ID.
  """
  @spec get_killmail(kill_id()) :: {:ok, kill_data()} | {:error, term()}
  def get_killmail(killmail_id) when is_integer(killmail_id) do
    case :ets.lookup(@killmails_table, killmail_id) do
      [{^killmail_id, killmail}] ->
        {:ok, killmail}

      [] ->
        {:error, "Killmail not found"}
    end
  end

  @doc """
  Deletes a killmail by ID.
  """
  @spec delete_killmail(kill_id()) :: :ok
  def delete_killmail(killmail_id) when is_integer(killmail_id) do
    :ets.delete(@killmails_table, killmail_id)
    :ok
  end

  @doc """
  Adds a killmail to a system's list.
  """
  @spec add_system_killmail(system_id(), kill_id()) :: :ok
  def add_system_killmail(system_id, killmail_id)
      when is_integer(system_id) and is_integer(killmail_id) do
    case :ets.lookup(@system_killmails_table, system_id) do
      [] ->
        :ets.insert(@system_killmails_table, {system_id, [killmail_id]})

      [{^system_id, existing_ids}] ->
        # Ensure we don't add duplicates
        if killmail_id not in existing_ids do
          :ets.insert(@system_killmails_table, {system_id, [killmail_id | existing_ids]})
        end
    end

    :ok
  end

  @doc """
  Gets all killmails for a system.
  """
  @spec get_killmails_for_system(system_id()) :: {:ok, [kill_id()]}
  def get_killmails_for_system(system_id) when is_integer(system_id) do
    case :ets.lookup(@system_killmails_table, system_id) do
      [{^system_id, killmail_ids}] -> {:ok, killmail_ids}
      [] -> {:ok, []}
    end
  end

  @doc """
  Removes a killmail from a system's list.
  """
  @spec remove_system_killmail(system_id(), kill_id()) :: :ok
  def remove_system_killmail(system_id, killmail_id)
      when is_integer(system_id) and is_integer(killmail_id) do
    case :ets.lookup(@system_killmails_table, system_id) do
      [] ->
        :ok

      [{^system_id, existing_ids}] ->
        new_ids = Enum.reject(existing_ids, &(&1 == killmail_id))

        if Enum.empty?(new_ids) do
          :ets.delete(@system_killmails_table, system_id)
        else
          :ets.insert(@system_killmails_table, {system_id, new_ids})
        end
    end

    :ok
  end

  @doc """
  Increments the kill count for a system.
  """
  @spec increment_system_kill_count(system_id()) :: :ok
  def increment_system_kill_count(system_id) when is_integer(system_id) do
    :ets.update_counter(@system_kill_counts_table, system_id, {2, 1}, {system_id, 0})
    :ok
  end

  @doc """
  Gets the kill count for a system.
  """
  @spec get_system_kill_count(system_id()) :: {:ok, non_neg_integer()}
  def get_system_kill_count(system_id) when is_integer(system_id) do
    case :ets.lookup(@system_kill_counts_table, system_id) do
      [{^system_id, count}] -> {:ok, count}
      [] -> {:ok, 0}
    end
  end

  @doc """
  Sets the fetch timestamp for a system.
  """
  @spec set_system_fetch_timestamp(system_id(), DateTime.t()) :: :ok
  def set_system_fetch_timestamp(system_id, timestamp) when is_integer(system_id) do
    :ets.insert(@system_fetch_timestamps_table, {system_id, timestamp})
    :ok
  end

  @doc """
  Gets the fetch timestamp for a system.
  """
  @spec get_system_fetch_timestamp(system_id()) :: {:ok, DateTime.t()} | {:error, term()}
  def get_system_fetch_timestamp(system_id) when is_integer(system_id) do
    case :ets.lookup(@system_fetch_timestamps_table, system_id) do
      [{^system_id, timestamp}] ->
        {:ok, timestamp}

      [] ->
        {:error, "No fetch timestamp found for system"}
    end
  end

  # ============================================================================
  # Cleanup and Utility Functions
  # ============================================================================

  @doc """
  Clears all data from all tables (for testing).
  """
  @spec clear_all() :: :ok
  def clear_all do
    :ets.delete_all_objects(@killmails_table)
    :ets.delete_all_objects(@killmail_events_table)
    :ets.delete_all_objects(@client_offsets_table)
    :ets.delete_all_objects(@counters_table)
    :ets.delete_all_objects(@system_killmails_table)
    :ets.delete_all_objects(@system_kill_counts_table)
    :ets.delete_all_objects(@system_fetch_timestamps_table)

    # Reinitialize counters
    :ets.insert(@counters_table, {:event_counter, 0})
    :ets.insert(@counters_table, {:killmail_seq, 0})
    :ok
  end

  @doc """
  Cleans up ETS tables for testing (alias for clear_all).
  """
  @spec cleanup_tables() :: :ok
  def cleanup_tables, do: clear_all()

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec get_next_event_id() :: event_id()
  defp get_next_event_id do
    :ets.update_counter(@counters_table, :event_counter, 1)
  end

  @spec get_offset_for_system(system_id(), client_offsets()) :: event_id()
  defp get_offset_for_system(system_id, offsets) do
    Map.get(offsets, system_id, 0)
  end

  defp update_client_offsets(sorted_events, client_offsets) do
    Enum.reduce(sorted_events, client_offsets, &update_offset_for_event/2)
  end

  defp update_offset_for_event({event_id, sys_id, _}, acc) do
    current_offset = Map.get(acc, sys_id, 0)
    if event_id > current_offset, do: Map.put(acc, sys_id, event_id), else: acc
  end
end
