defmodule WandererKills.Data.Stores.KillmailStore do
  @moduledoc """
  GenServer-based killmail event store using ETS tables for real-time distribution.

  Integrates with the existing WandererKills parser pipeline to provide:
  - Event-sourced killmail storage with sequential IDs
  - Client offset tracking for reliable delivery
  - Phoenix PubSub for real-time notifications
  - HTTP endpoints for polling and backfill
  """

  use GenServer
  require Logger

  alias WandererKills.Infrastructure.Config
  alias WandererKills.Infrastructure.Error

  @type event_id :: integer()
  @type system_id :: integer()
  @type client_id :: String.t()
  @type killmail_map :: map()
  @type client_offsets :: %{system_id() => event_id()}
  @type killmail :: map()
  @type killmail_id :: integer()
  @type timestamp :: DateTime.t()

  # Table names as module attributes for easy reference
  @killmail_events :killmail_events
  @client_offsets :client_offsets
  @counters :counters
  @killmails :killmails
  @system_killmails :system_killmails
  @system_kill_counts :system_kill_counts
  @system_fetch_timestamps :system_fetch_timestamps

  # Public API

  @doc """
  Starts the KillmailStore GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Cleans up ETS tables for testing.
  """
  def cleanup_tables do
    safe_delete_all_objects(@killmail_events)
    safe_delete_all_objects(@client_offsets)
    safe_delete_all_objects(@counters)
    safe_delete_all_objects(@killmails)
    safe_delete_all_objects(@system_killmails)
    safe_delete_all_objects(@system_kill_counts)
    safe_delete_all_objects(@system_fetch_timestamps)

    # Safely insert counter if table exists
    try do
      case :ets.whereis(@counters) do
        :undefined -> :ok
        _ -> :ets.insert(@counters, {:killmail_seq, 0})
      end
    rescue
      ArgumentError -> :ok
    end
  end

  @doc """
  Inserts a new killmail event for the given system.

  ## Parameters
  - `system_id` - The solar system ID where the killmail occurred
  - `killmail_map` - The processed killmail data from the parser

  ## Returns
  - `:ok` - Event successfully inserted and broadcast
  """
  @spec insert_event(system_id(), killmail_map()) :: :ok
  def insert_event(system_id, killmail_map) do
    GenServer.call(
      __MODULE__,
      {:insert, system_id, killmail_map},
      WandererKills.Infrastructure.Constants.timeout(:gen_server_call)
    )
  end

  @doc """
  Fetches all new events for a client across multiple systems.

  ## Parameters
  - `client_id` - Unique identifier for the client
  - `system_ids` - List of system IDs the client is interested in

  ## Returns
  - `{:ok, events}` - List of `{event_id, system_id, killmail}` tuples
  """
  @spec fetch_for_client(client_id(), [system_id()]) ::
          {:ok, [{event_id(), system_id(), killmail_map()}]}
  def fetch_for_client(client_id, system_ids) do
    GenServer.call(
      __MODULE__,
      {:fetch, client_id, system_ids},
      WandererKills.Infrastructure.Constants.timeout(:gen_server_call)
    )
  end

  @doc """
  Fetches the next single event for a client across multiple systems.

  ## Parameters
  - `client_id` - Unique identifier for the client
  - `system_ids` - List of system IDs the client is interested in

  ## Returns
  - `{:ok, {event_id, system_id, killmail}}` - The next event
  - `:empty` - No new events available
  """
  @spec fetch_one_event(client_id(), system_id() | [system_id()]) ::
          {:ok, {event_id(), system_id(), killmail_map()}} | :empty
  def fetch_one_event(client_id, system_ids) when is_integer(system_ids) do
    fetch_one_event(client_id, [system_ids])
  end

  def fetch_one_event(client_id, system_ids) when is_list(system_ids) do
    GenServer.call(
      __MODULE__,
      {:fetch_one, client_id, system_ids},
      WandererKills.Infrastructure.Constants.timeout(:gen_server_call)
    )
  end

  @doc """
  Stores a killmail in the store.
  """
  def store_killmail(killmail) do
    GenServer.call(__MODULE__, {:store_killmail, killmail})
  end

  @doc """
  Retrieves a killmail by ID.
  """
  def get_killmail(killmail_id) do
    GenServer.call(__MODULE__, {:get_killmail, killmail_id})
  end

  @doc """
  Deletes a killmail by ID.
  """
  def delete_killmail(killmail_id) do
    GenServer.call(__MODULE__, {:delete_killmail, killmail_id})
  end

  @doc """
  Adds a killmail to a system's list.
  """
  def add_system_killmail(system_id, killmail_id) do
    GenServer.call(__MODULE__, {:add_system_killmail, system_id, killmail_id})
  end

  @doc """
  Gets all killmails for a system.
  """
  def get_killmails_for_system(system_id) do
    GenServer.call(__MODULE__, {:get_killmails_for_system, system_id})
  end

  @doc """
  Removes a killmail from a system's list.
  """
  def remove_system_killmail(system_id, killmail_id) do
    GenServer.call(__MODULE__, {:remove_system_killmail, system_id, killmail_id})
  end

  @doc """
  Increments the kill count for a system.
  """
  def increment_system_kill_count(system_id) do
    GenServer.call(__MODULE__, {:increment_system_kill_count, system_id})
  end

  @doc """
  Gets the kill count for a system.
  """
  def get_system_kill_count(system_id) do
    GenServer.call(__MODULE__, {:get_system_kill_count, system_id})
  end

  @doc """
  Sets the fetch timestamp for a system.
  """
  def set_system_fetch_timestamp(system_id, timestamp) do
    GenServer.call(__MODULE__, {:set_system_fetch_timestamp, system_id, timestamp})
  end

  @doc """
  Gets the fetch timestamp for a system.
  """
  def get_system_fetch_timestamp(system_id) do
    GenServer.call(__MODULE__, {:get_system_fetch_timestamp, system_id})
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting KillmailStore GenServer")

    # ETS tables are now managed by ETSSupervisor and should already exist
    # Verify that required tables are available
    required_tables = [
      @killmail_events,
      @client_offsets,
      @counters,
      @killmails,
      @system_killmails,
      @system_kill_counts,
      @system_fetch_timestamps
    ]

    case verify_tables_exist(required_tables) do
      :ok ->
        Logger.debug("All required ETS tables are available")

      {:error, missing_tables} ->
        Logger.error("Missing required ETS tables", missing_tables: missing_tables)
        # Continue anyway, tables might be created asynchronously
    end

    # Schedule garbage collection
    schedule_garbage_collection()

    {:ok,
     %{
       started_at: DateTime.utc_now(),
       tables_verified: true
     }}
  end

  # Helper function to verify that required tables exist
  @spec verify_tables_exist([atom()]) :: :ok | {:error, [atom()]}
  defp verify_tables_exist(table_names) do
    missing_tables =
      Enum.filter(table_names, fn table_name ->
        case :ets.whereis(table_name) do
          :undefined -> true
          _ -> false
        end
      end)

    case missing_tables do
      [] -> :ok
      missing -> {:error, missing}
    end
  end

  @impl true
  def handle_call({:insert, system_id, killmail_map}, _from, state) do
    # Get next event ID
    [{:killmail_seq, event_id}] = :ets.lookup(:counters, :killmail_seq)
    :ets.insert(:counters, {:killmail_seq, event_id + 1})

    # Store the killmail
    killmail_id = killmail_map["killmail_id"]
    :ets.insert(:killmails, {killmail_id, killmail_map})

    # Add to system killmails
    case :ets.lookup(:system_killmails, system_id) do
      [] ->
        :ets.insert(:system_killmails, {system_id, [killmail_id]})

      [{^system_id, existing_ids}] ->
        # Ensure we don't add duplicates
        if killmail_id not in existing_ids do
          :ets.insert(:system_killmails, {system_id, [killmail_id | existing_ids]})
        end
    end

    # Insert event
    :ets.insert(:killmail_events, {event_id, system_id, killmail_map})

    # Broadcast via PubSub
    Phoenix.PubSub.broadcast(
      WandererKills.PubSub,
      "system:#{system_id}",
      {:new_killmail, system_id, killmail_map}
    )

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:fetch, client_id, system_ids}, _from, state) do
    # Get client offsets
    client_offsets = get_client_offsets(client_id)

    # Handle empty system list
    if Enum.empty?(system_ids) do
      {:reply, {:ok, []}, state}
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
      events = :ets.select(:killmail_events, match_spec)

      # Sort by event_id ascending
      sorted_events = Enum.sort_by(events, &elem(&1, 0))

      # Update client offsets for each system
      updated_offsets = update_client_offsets(sorted_events, client_offsets)

      # Store updated offsets
      :ets.insert(:client_offsets, {client_id, updated_offsets})

      {:reply, {:ok, sorted_events}, state}
    end
  end

  @impl true
  def handle_call({:fetch_one, client_id, system_ids}, _from, state) do
    # Get client offsets
    client_offsets = get_client_offsets(client_id)

    # Handle empty system list
    if Enum.empty?(system_ids) do
      {:reply, :empty, state}
    else
      fetch_one_event(client_id, system_ids, client_offsets, state)
    end
  end

  @impl true
  def handle_call({:store_killmail, killmail}, _from, state) when is_map(killmail) do
    killmail_id = killmail["killmail_id"]

    if killmail_id do
      :ets.insert(:killmails, {killmail_id, killmail})
      {:reply, :ok, state}
    else
      {:reply, {:error, Error.validation_error("Killmail missing required killmail_id field")},
       state}
    end
  end

  def handle_call({:store_killmail, _invalid}, _from, state) do
    {:reply, {:error, Error.validation_error("Invalid killmail format - must be a map")}, state}
  end

  @impl true
  def handle_call({:get_killmail, killmail_id}, _from, state) do
    case :ets.lookup(:killmails, killmail_id) do
      [{^killmail_id, killmail}] ->
        {:reply, {:ok, killmail}, state}

      [] ->
        {:reply,
         {:error, Error.not_found_error("Killmail not found", %{killmail_id: killmail_id})},
         state}
    end
  end

  @impl true
  def handle_call({:delete_killmail, killmail_id}, _from, state) do
    :ets.delete(:killmails, killmail_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:add_system_killmail, system_id, killmail_id}, _from, state) do
    case :ets.lookup(:system_killmails, system_id) do
      [] ->
        :ets.insert(:system_killmails, {system_id, [killmail_id]})

      [{^system_id, existing_ids}] ->
        # Ensure we don't add duplicates
        if killmail_id not in existing_ids do
          :ets.insert(:system_killmails, {system_id, [killmail_id | existing_ids]})
        end
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_killmails_for_system, system_id}, _from, state) do
    case :ets.lookup(:system_killmails, system_id) do
      [{^system_id, killmail_ids}] -> {:reply, {:ok, killmail_ids}, state}
      [] -> {:reply, {:ok, []}, state}
    end
  end

  @impl true
  def handle_call({:remove_system_killmail, system_id, killmail_id}, _from, state) do
    case :ets.lookup(:system_killmails, system_id) do
      [] ->
        :ok

      [{^system_id, existing_ids}] ->
        new_ids = Enum.reject(existing_ids, &(&1 == killmail_id))

        if Enum.empty?(new_ids) do
          :ets.delete(:system_killmails, system_id)
        else
          :ets.insert(:system_killmails, {system_id, new_ids})
        end
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:increment_system_kill_count, system_id}, _from, state) do
    _count = :ets.update_counter(:system_kill_counts, system_id, {2, 1}, {system_id, 0})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_system_kill_count, system_id}, _from, state) do
    case :ets.lookup(:system_kill_counts, system_id) do
      [{^system_id, count}] -> {:reply, {:ok, count}, state}
      [] -> {:reply, {:ok, 0}, state}
    end
  end

  @impl true
  def handle_call({:set_system_fetch_timestamp, system_id, timestamp}, _from, state) do
    :ets.insert(:system_fetch_timestamps, {system_id, timestamp})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_system_fetch_timestamp, system_id}, _from, state) do
    case :ets.lookup(:system_fetch_timestamps, system_id) do
      [{^system_id, timestamp}] ->
        {:reply, {:ok, timestamp}, state}

      [] ->
        {:reply,
         {:error,
          Error.not_found_error("No fetch timestamp found for system", %{system_id: system_id})},
         state}
    end
  end

  @impl true
  def handle_cast(:garbage_collect, state) do
    perform_garbage_collection()
    schedule_garbage_collection()
    {:noreply, state}
  end

  @impl true
  def handle_info({:garbage_collect}, state) do
    perform_garbage_collection()
    schedule_garbage_collection()
    {:noreply, state}
  end

  # Private Functions

  defp fetch_one_event(client_id, system_ids, client_offsets, state) do
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
    case :ets.select(:killmail_events, match_spec, 1) do
      {[{event_id, sys_id, km}], _continuation} ->
        # Update offset for this system only
        updated_offsets = Map.put(client_offsets, sys_id, event_id)
        :ets.insert(:client_offsets, {client_id, updated_offsets})

        {:reply, {:ok, {event_id, sys_id, km}}, state}

      {[], _continuation} ->
        {:reply, :empty, state}

      :"$end_of_table" ->
        {:reply, :empty, state}
    end
  end

  @spec get_client_offsets(client_id()) :: client_offsets()
  defp get_client_offsets(client_id) do
    case :ets.lookup(:client_offsets, client_id) do
      [{^client_id, offsets}] -> offsets
      [] -> %{}
    end
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

  @spec schedule_garbage_collection() :: :ok
  defp schedule_garbage_collection do
    gc_interval = Config.killmail_store(:gc_interval_ms)
    Process.send_after(self(), {:garbage_collect}, gc_interval)
    :ok
  end

  @spec perform_garbage_collection() :: :ok
  defp perform_garbage_collection do
    # Get all client offsets
    all_offsets = :ets.tab2list(:client_offsets)

    # Find the global minimum offset across all systems
    min_offset =
      case all_offsets do
        [] ->
          # No clients, don't delete anything yet
          0

        offset_list ->
          offset_list
          |> Enum.flat_map(fn {_client_id, offsets} -> Map.values(offsets) end)
          |> case do
            [] -> 0
            values -> Enum.min(values)
          end
      end

    # Delete events with event_id <= min_offset
    if min_offset > 0 do
      deleted_count =
        :ets.select_delete(:killmail_events, [
          {{:"$1", :"$2", :"$3"}, [{:"=<", :"$1", min_offset}], [true]}
        ])

      Logger.info("Garbage collected killmail events", %{
        min_offset: min_offset,
        deleted_count: deleted_count
      })
    end

    :ok
  end

  # Helper function to safely delete all objects from a table
  defp safe_delete_all_objects(table_name) do
    try do
      case :ets.whereis(table_name) do
        :undefined -> :ok
        _ -> :ets.delete_all_objects(table_name)
      end
    rescue
      ArgumentError -> :ok
    end
  end
end
