defmodule WandererKills.Storage.KillmailStore do
  @moduledoc """
  Unified ETS-backed killmail storage with optional event streaming support.

  This module consolidates the functionality of both the basic Store and 
  the event-streaming KillStore into a single implementation. Event streaming
  features can be enabled/disabled via configuration.

  ## Features

  - Core killmail storage and retrieval
  - System-based killmail organization
  - Optional event streaming for real-time updates
  - Client offset tracking for event consumption
  - Fetch timestamp management
  - Kill count statistics

  ## Configuration

  ```elixir
  config :wanderer_kills, :storage,
    enable_event_streaming: true  # Default: true
  ```
  """

  @behaviour WandererKills.Storage.Behaviour

  require Logger
  alias WandererKills.Support.Error
  alias WandererKills.Config

  # ETS tables
  @killmails_table :killmails
  @system_killmails_table :system_killmails
  @system_kill_counts_table :system_kill_counts
  @system_fetch_timestamps_table :system_fetch_timestamps

  # Event streaming tables (optional)
  @killmail_events_table :killmail_events
  @client_offsets_table :client_offsets
  @counters_table :counters

  @type killmail_id :: integer()
  @type system_id :: integer()
  @type killmail_data :: map()
  @type event_id :: integer()
  @type client_id :: term()
  @type client_offsets :: %{system_id() => event_id()}
  @type event_tuple :: {event_id(), system_id(), killmail_data()}

  # ============================================================================
  # Table Initialization
  # ============================================================================

  @doc """
  Initializes all required ETS tables at application start.
  """
  @impl true
  def init_tables! do
    # Core tables
    :ets.new(@killmails_table, [:set, :named_table, :public, {:read_concurrency, true}])
    :ets.new(@system_killmails_table, [:set, :named_table, :public, {:read_concurrency, true}])
    :ets.new(@system_kill_counts_table, [:set, :named_table, :public, {:read_concurrency, true}])

    :ets.new(@system_fetch_timestamps_table, [
      :set,
      :named_table,
      :public,
      {:read_concurrency, true}
    ])

    tables = [
      @killmails_table,
      @system_killmails_table,
      @system_kill_counts_table,
      @system_fetch_timestamps_table
    ]

    # Event streaming tables (if enabled)
    if event_streaming_enabled?() do
      :ets.new(@killmail_events_table, [
        :ordered_set,
        :named_table,
        :public,
        {:read_concurrency, true}
      ])

      :ets.new(@client_offsets_table, [:set, :named_table, :public, {:read_concurrency, true}])
      :ets.new(@counters_table, [:set, :named_table, :public, {:read_concurrency, true}])

      # Initialize counters
      :ets.insert(@counters_table, {:event_counter, 0})
      :ets.insert(@counters_table, {:killmail_seq, 0})

      event_tables = [@killmail_events_table, @client_offsets_table, @counters_table]
      all_tables = tables ++ event_tables

      Logger.info("Initialized KillmailStore ETS tables: #{inspect(all_tables)}")
    else
      Logger.info("Initialized KillmailStore ETS tables: #{inspect(tables)}")
    end

    :ok
  end

  # ============================================================================
  # Core Storage Operations
  # ============================================================================

  @doc """
  Stores a killmail without system association.
  """
  @impl true
  def put(killmail_id, killmail_data) when is_integer(killmail_id) and is_map(killmail_data) do
    :ets.insert(@killmails_table, {killmail_id, killmail_data})
    :ok
  end

  @doc """
  Stores a killmail with system association.
  """
  @impl true
  def put(killmail_id, system_id, killmail_data)
      when is_integer(killmail_id) and is_integer(system_id) and is_map(killmail_data) do
    # Store the killmail
    :ets.insert(@killmails_table, {killmail_id, killmail_data})

    # Associate with system
    add_system_killmail(system_id, killmail_id)

    :ok
  end

  @doc """
  Retrieves a killmail by ID.
  """
  @impl true
  def get(killmail_id) when is_integer(killmail_id) do
    case :ets.lookup(@killmails_table, killmail_id) do
      [{^killmail_id, data}] ->
        {:ok, data}

      [] ->
        {:error, Error.not_found_error("Killmail not found", %{killmail_id: killmail_id})}
    end
  end

  @doc """
  Deletes a killmail from the store.
  """
  @impl true
  def delete(killmail_id) when is_integer(killmail_id) do
    # Delete from main table
    :ets.delete(@killmails_table, killmail_id)

    # Remove from all system associations
    :ets.foldl(
      fn {system_id, killmail_ids}, _acc ->
        remove_killmail_from_system(system_id, killmail_ids, killmail_id)
      end,
      :ok,
      @system_killmails_table
    )

    :ok
  end

  @doc """
  Lists all killmails for a specific system.
  """
  @impl true
  def list_by_system(system_id) when is_integer(system_id) do
    case :ets.lookup(@system_killmails_table, system_id) do
      [{^system_id, killmail_ids}] ->
        Enum.flat_map(killmail_ids, &get_killmail_data/1)

      [] ->
        []
    end
  end

  # ============================================================================
  # System Operations
  # ============================================================================

  @doc """
  Adds a killmail to a system's list.

  Optimized to minimize list traversal by checking existence only when the list is small.
  For larger lists, duplicates are rare so we skip the check.
  """
  @impl true
  def add_system_killmail(system_id, killmail_id)
      when is_integer(system_id) and is_integer(killmail_id) do
    case :ets.lookup(@system_killmails_table, system_id) do
      [] ->
        :ets.insert(@system_killmails_table, {system_id, [killmail_id]})

      [{^system_id, existing_ids}] when length(existing_ids) < 100 ->
        # For small lists, check for duplicates using simple list membership
        if killmail_id not in existing_ids do
          :ets.insert(@system_killmails_table, {system_id, [killmail_id | existing_ids]})
        end

      [{^system_id, existing_ids}] ->
        # For large lists, skip duplicate check as duplicates are rare
        # and the O(n) check becomes expensive
        :ets.insert(@system_killmails_table, {system_id, [killmail_id | existing_ids]})
    end

    :ok
  end

  @doc """
  Gets all killmail IDs for a system.
  """
  @impl true
  def get_killmails_for_system(system_id) when is_integer(system_id) do
    case :ets.lookup(@system_killmails_table, system_id) do
      [{^system_id, killmail_ids}] -> {:ok, killmail_ids}
      [] -> {:ok, []}
    end
  end

  @doc """
  Removes a killmail from a system's list.
  """
  @impl true
  def remove_system_killmail(system_id, killmail_id)
      when is_integer(system_id) and is_integer(killmail_id) do
    case :ets.lookup(@system_killmails_table, system_id) do
      [] ->
        :ok

      [{^system_id, existing_ids}] ->
        new_ids = List.delete(existing_ids, killmail_id)

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
  @impl true
  def increment_system_killmail_count(system_id) when is_integer(system_id) do
    :ets.update_counter(@system_kill_counts_table, system_id, {2, 1}, {system_id, 0})
    :ok
  end

  @doc """
  Gets the kill count for a system.
  """
  @impl true
  def get_system_killmail_count(system_id) when is_integer(system_id) do
    case :ets.lookup(@system_kill_counts_table, system_id) do
      [{^system_id, count}] -> {:ok, count}
      [] -> {:ok, 0}
    end
  end

  # ============================================================================
  # Timestamp Operations
  # ============================================================================

  @doc """
  Sets the fetch timestamp for a system.
  """
  @impl true
  def set_system_fetch_timestamp(system_id, timestamp)
      when is_integer(system_id) and is_struct(timestamp, DateTime) do
    :ets.insert(@system_fetch_timestamps_table, {system_id, timestamp})
    :ok
  end

  @doc """
  Gets the fetch timestamp for a system.
  """
  @impl true
  def get_system_fetch_timestamp(system_id) when is_integer(system_id) do
    case :ets.lookup(@system_fetch_timestamps_table, system_id) do
      [{^system_id, timestamp}] ->
        {:ok, timestamp}

      [] ->
        {:error,
         Error.not_found_error("No fetch timestamp found for system", %{system_id: system_id})}
    end
  end

  # ============================================================================
  # Event Streaming Operations
  # ============================================================================

  @doc """
  Inserts a new killmail event for streaming (if enabled).
  """
  @impl true
  def insert_event(system_id, killmail_map) when is_integer(system_id) and is_map(killmail_map) do
    if event_streaming_enabled?() do
      # Get next event ID
      event_id = get_next_event_id()

      # Store the killmail
      killmail_id = killmail_map["killmail_id"]
      :ets.insert(@killmails_table, {killmail_id, killmail_map})

      # Add to system killmails
      add_system_killmail(system_id, killmail_id)

      # Insert event for streaming
      :ets.insert(@killmail_events_table, {event_id, system_id, killmail_map})

      # Broadcast via PubSub
      Phoenix.PubSub.broadcast(
        WandererKills.PubSub,
        "system:#{system_id}",
        {:new_killmail, system_id, killmail_map}
      )
    else
      # Just store without event streaming
      killmail_id = killmail_map["killmail_id"]
      put(killmail_id, system_id, killmail_map)
    end

    :ok
  end

  @doc """
  Fetches all new events for a client (if event streaming enabled).
  """
  @impl true
  def fetch_for_client(client_id, system_ids) when is_list(system_ids) do
    if event_streaming_enabled?() do
      do_fetch_for_client(client_id, system_ids)
    else
      {:ok, []}
    end
  end

  @doc """
  Fetches the next single event for a client (if event streaming enabled).
  """
  @impl true
  def fetch_one_event(client_id, system_ids) when is_list(system_ids) do
    if event_streaming_enabled?() do
      do_fetch_one_event(client_id, system_ids)
    else
      :empty
    end
  end

  def fetch_one_event(client_id, system_id) when is_integer(system_id) do
    fetch_one_event(client_id, [system_id])
  end

  @doc """
  Gets client offsets for event streaming.
  """
  @impl true
  def get_client_offsets(client_id) do
    if event_streaming_enabled?() do
      case :ets.lookup(@client_offsets_table, client_id) do
        [{^client_id, offsets}] when is_map(offsets) -> offsets
        [] -> %{}
      end
    else
      %{}
    end
  end

  @doc """
  Updates client offsets for event streaming.
  """
  @impl true
  def put_client_offsets(client_id, offsets) when is_map(offsets) do
    if event_streaming_enabled?() do
      :ets.insert(@client_offsets_table, {client_id, offsets})
    end

    :ok
  end

  # ============================================================================
  # Maintenance Operations
  # ============================================================================

  @doc """
  Clears all data from all tables (for testing).
  """
  @impl true
  def clear do
    :ets.delete_all_objects(@killmails_table)
    :ets.delete_all_objects(@system_killmails_table)
    :ets.delete_all_objects(@system_kill_counts_table)
    :ets.delete_all_objects(@system_fetch_timestamps_table)

    if event_streaming_enabled?() do
      :ets.delete_all_objects(@killmail_events_table)
      :ets.delete_all_objects(@client_offsets_table)
      :ets.delete_all_objects(@counters_table)

      # Reinitialize counters
      :ets.insert(@counters_table, {:event_counter, 0})
      :ets.insert(@counters_table, {:killmail_seq, 0})
    end

    :ok
  end

  # ============================================================================
  # Legacy API Support
  # ============================================================================

  # These functions provide backward compatibility with existing code

  @doc false
  def store_killmail(killmail) when is_map(killmail) do
    killmail_id = killmail["killmail_id"]

    if killmail_id do
      put(killmail_id, killmail)
    else
      {:error,
       Error.validation_error(:missing_killmail_id, "Killmail missing required killmail_id field")}
    end
  end

  @doc false
  def get_killmail(killmail_id) when is_integer(killmail_id) do
    get(killmail_id)
  end

  @doc false
  def delete_killmail(killmail_id) when is_integer(killmail_id) do
    delete(killmail_id)
  end

  @doc false
  def fetch_events(client_id, system_ids, limit \\ 100)
      when is_list(system_ids) and is_integer(limit) do
    case fetch_for_client(client_id, system_ids) do
      {:ok, events} ->
        events
        |> Enum.take(limit)
        |> Enum.map(&elem(&1, 2))
    end
  end

  @doc false
  def fetch_timestamp(system_id, timestamp) when is_integer(system_id) do
    set_system_fetch_timestamp(system_id, timestamp)
  end

  @doc false
  def fetch_timestamp(system_id) when is_integer(system_id) do
    get_system_fetch_timestamp(system_id)
  end

  @doc false
  def cleanup_tables, do: clear()

  @doc false
  def clear_all, do: clear()

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp event_streaming_enabled? do
    Config.storage().enable_event_streaming
  end

  defp get_killmail_data(killmail_id) do
    case :ets.lookup(@killmails_table, killmail_id) do
      [{^killmail_id, killmail_data}] -> [killmail_data]
      [] -> []
    end
  end

  defp get_next_event_id do
    :ets.update_counter(@counters_table, :event_counter, 1)
  end

  defp get_offset_for_system(system_id, offsets) do
    Map.get(offsets, system_id, 0)
  end

  defp do_fetch_for_client(client_id, system_ids) do
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

  defp do_fetch_one_event(client_id, system_ids) do
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

  defp update_client_offsets(sorted_events, client_offsets) do
    Enum.reduce(sorted_events, client_offsets, &update_offset_for_event/2)
  end

  defp update_offset_for_event({event_id, sys_id, _}, acc) do
    current_offset = Map.get(acc, sys_id, 0)
    if event_id > current_offset, do: Map.put(acc, sys_id, event_id), else: acc
  end

  defp remove_killmail_from_system(system_id, killmail_ids, killmail_id) do
    if killmail_id in killmail_ids do
      updated_ids = List.delete(killmail_ids, killmail_id)

      if Enum.empty?(updated_ids) do
        :ets.delete(@system_killmails_table, system_id)
      else
        :ets.insert(@system_killmails_table, {system_id, updated_ids})
      end
    end

    :ok
  end
end
