defmodule WandererKills.KillmailStore do
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

  alias WandererKills.Config

  @type event_id :: integer()
  @type system_id :: integer()
  @type client_id :: String.t()
  @type killmail_map :: map()
  @type client_offsets :: %{system_id() => event_id()}

  # Public API

  @doc """
  Starts the KillmailStore GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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
    GenServer.call(__MODULE__, {:insert, system_id, killmail_map})
  end

  @doc """
  Fetches all new events for a client across multiple systems.

  ## Parameters
  - `client_id` - Unique identifier for the client
  - `system_ids` - List of system IDs the client is interested in

  ## Returns
  - `{:ok, events}` - List of `{event_id, system_id, killmail}` tuples
  """
  @spec fetch_for_client(client_id(), [system_id()]) :: {:ok, [{event_id(), system_id(), killmail_map()}]}
  def fetch_for_client(client_id, system_ids) do
    GenServer.call(__MODULE__, {:fetch, client_id, system_ids})
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
  @spec fetch_one_event(client_id(), [system_id()]) ::
    {:ok, {event_id(), system_id(), killmail_map()}} | :empty
  def fetch_one_event(client_id, system_ids) do
    GenServer.call(__MODULE__, {:fetch_one, client_id, system_ids})
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting KillmailStore with ETS tables")

    # Create ETS tables
    :ets.new(:killmail_events, [:ordered_set, :public, :named_table])
    :ets.new(:client_offsets, [:set, :public, :named_table])
    :ets.new(:counters, [:set, :public, :named_table])

    # Initialize sequence counter
    :ets.insert(:counters, {:killmail_seq, 0})

    # Schedule garbage collection
    schedule_garbage_collection()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:insert, system_id, killmail_map}, _from, state) do
    # Get and increment sequence counter
    [{:killmail_seq, current_seq}] = :ets.lookup(:counters, :killmail_seq)
    new_seq = current_seq + 1
    :ets.insert(:counters, {:killmail_seq, new_seq})

    # Insert event into events table
    :ets.insert(:killmail_events, {new_seq, system_id, killmail_map})

    # Broadcast to PubSub
    Phoenix.PubSub.broadcast!(
      WandererKills.PubSub,
      "system:#{system_id}",
      {:new_killmail, system_id, killmail_map}
    )

    Logger.debug("Inserted killmail event", %{
      event_id: new_seq,
      system_id: system_id,
      killmail_id: killmail_map["killmail_id"]
    })

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:fetch, client_id, system_ids}, _from, state) do
    # Get client offsets
    client_offsets = get_client_offsets(client_id)

    # Collect matching events
    events = :ets.foldl(fn {event_id, sys_id, km}, acc ->
      if sys_id in system_ids and event_id > get_offset_for_system(sys_id, client_offsets) do
        [{event_id, sys_id, km} | acc]
      else
        acc
      end
    end, [], :killmail_events)

    # Sort by event_id ascending
    sorted_events = Enum.sort_by(events, &elem(&1, 0))

    # Update client offsets
    updated_offsets = update_client_offsets(client_offsets, sorted_events)
    :ets.insert(:client_offsets, {client_id, updated_offsets})

    Logger.debug("Fetched events for client", %{
      client_id: client_id,
      system_ids: system_ids,
      event_count: length(sorted_events)
    })

    {:reply, {:ok, sorted_events}, state}
  end

  @impl true
  def handle_call({:fetch_one, client_id, system_ids}, _from, state) do
    # Get client offsets
    client_offsets = get_client_offsets(client_id)

    # Find the single event with the smallest event_id
    result = :ets.foldl(fn {event_id, sys_id, km}, acc ->
      if sys_id in system_ids and event_id > get_offset_for_system(sys_id, client_offsets) do
        case acc do
          nil -> {event_id, sys_id, km}
          {current_event_id, _, _} when event_id < current_event_id -> {event_id, sys_id, km}
          _ -> acc
        end
      else
        acc
      end
    end, nil, :killmail_events)

    case result do
      nil ->
        {:reply, :empty, state}

      {event_id, sys_id, km} ->
        # Update offset for this system only
        updated_offsets = Map.put(client_offsets, sys_id, event_id)
        :ets.insert(:client_offsets, {client_id, updated_offsets})

        Logger.debug("Fetched single event for client", %{
          client_id: client_id,
          event_id: event_id,
          system_id: sys_id
        })

        {:reply, {:ok, {event_id, sys_id, km}}, state}
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

  @spec update_client_offsets(client_offsets(), [{event_id(), system_id(), killmail_map()}]) :: client_offsets()
  defp update_client_offsets(current_offsets, events) do
    # Group events by system_id and take the max event_id for each system
    max_event_ids = events
    |> Enum.group_by(&elem(&1, 1))  # Group by system_id
    |> Enum.map(fn {sys_id, sys_events} ->
      max_event_id = sys_events |> Enum.map(&elem(&1, 0)) |> Enum.max()
      {sys_id, max_event_id}
    end)
    |> Enum.into(%{})

    Map.merge(current_offsets, max_event_ids)
  end

  @spec schedule_garbage_collection() :: :ok
  defp schedule_garbage_collection do
    config = Config.killmail_store()
    Process.send_after(self(), {:garbage_collect}, config.gc_interval_ms)
    :ok
  end

  @spec perform_garbage_collection() :: :ok
  defp perform_garbage_collection do
    # Get all client offsets
    all_offsets = :ets.tab2list(:client_offsets)

    # Find the global minimum offset across all systems
    min_offset = case all_offsets do
      [] ->
        0  # No clients, don't delete anything yet

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
      deleted_count = :ets.select_delete(:killmail_events, [
        {{:"$1", :"$2", :"$3"}, [{:"=<", :"$1", min_offset}], [true]}
      ])

      Logger.info("Garbage collected killmail events", %{
        min_offset: min_offset,
        deleted_count: deleted_count
      })
    end

    :ok
  end
end
