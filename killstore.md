Create a new GenServer module MyApp.KillmailStore that, on init/1, does the following:

Creates an ETS table named :killmail_events of type :ordered_set, public, named table.

Creates an ETS table named :client_offsets of type :set, public, named table.

Creates an ETS table named :counters of type :set, public, named table, and inserts {:killmail_seq, 0}.

Returns {:ok, %{}} as its initial state.

Implement a public function insert_event(system_id :: integer(), killmail_map :: map()) :: :ok in MyApp.KillmailStore that:

Calls GenServer.call(**MODULE**, {:insert, system_id, killmail_map}).

In the GenServer’s handle_call({:insert, system_id, killmail_map}, \_from, state), does the following:

Reads the current counter from :counters (:killmail_seq), increments it by 1, and writes it back as the new :killmail_seq.

Inserts {new_seq, system_id, killmail_map} into ETS table :killmail_events.

Broadcasts via Phoenix.PubSub.broadcast!/3 on topic "system:#{system_id}" with message {:new_killmail, system_id, killmail_map}.

Replies {:reply, :ok, state}.

Implement a public function fetch_for_client(client_id :: String.t(), system_ids :: [integer()]) :: {:ok, [{integer(), integer(), map()}]} in MyApp.KillmailStore that:

Calls GenServer.call(**MODULE**, {:fetch, client_id, system_ids}).

In the GenServer’s handle_call({:fetch, client_id, system_ids}, \_from, state), does the following:

Looks up ETS :client_offsets for key client_id. If none, uses %{} as offsets.

Iterates over every ETS row in :killmail_events (via :ets.foldl/3) to collect [{event_id, sys_id, km} | acc] where sys_id is in system_ids and event_id > offset_for(sys_id, offsets).

Sorts the resulting list ascending by event_id.

Builds updated_offsets by taking the max event_id per sys_id in that list and merging into the client’s offsets map.

Writes :ets.insert(:client_offsets, {client_id, updated_offsets}).

Replies {:reply, {:ok, sorted_events}, state}.

Implement a public function fetch_one_event(client_id :: String.t(), system_ids :: [integer()]) :: {:ok, {event_id :: integer(), system_id :: integer(), killmail_map :: map()}} | :empty in MyApp.KillmailStore that:

Calls GenServer.call(**MODULE**, {:fetch_one, client_id, system_ids}).

In the GenServer’s handle_call({:fetch_one, client_id, system_ids}, \_from, state), does the following:

Reads ETS :client_offsets for client_id or defaults to %{}.

Uses :ets.foldl/3 to scan every {event_id, sys_id, km} in :killmail_events, and keeps only the single tuple with the smallest event_id such that sys_id in system_ids and event_id > offset_for(sys_id).

If no matching row is found, replies {:reply, :empty, state}.

Otherwise, updates the offset for that single sys_id in ETS :client_offsets to the returned event_id.

Replies {:reply, {:ok, {event_id, sys_id, km}}, state}.

Add a periodic “garbage‐collection” process (GenServer.cast/2) inside MyApp.KillmailStore that runs every 60 seconds (via Process.send_after/3) and does:

Reads all client‐offset maps from :client_offsets (via :ets.tab2list/1), merges them to find the global minimum min_offset across all systems.

Deletes every ETS row in :killmail_events with event_id <= min_offset (use :ets.select_delete/2 or :ets.foldl/3 + :ets.delete_object/2).

Schedules itself to run again in 60_000 ms.

Register MyApp.KillmailStore in the application supervision tree (e.g. in lib/my_app/application.ex) under children so it starts on boot, e.g.:

elixir
Copy
Edit
children = [
MyApp.KillmailStore,
{Phoenix.PubSub, name: MyApp.PubSub},

# … other children …

]
Ensure :phoenix_pubsub is listed as an application dependency in mix.exs, and verify config/config.exs contains:

elixir
Copy
Edit
config :my_app, MyApp.PubSub,
adapter: Phoenix.PubSub.PG2
Create a Phoenix Controller MyAppWeb.KillfeedController with two actions:

poll/2 for batch fetch:

Accepts client_id and systems as query params (e.g. GET /killfeed?client_id=foo&systems[]=30000142&systems[]=30000143).

Calls MyApp.KillmailStore.fetch_for_client(client_id, system_list) and returns 200 with JSON events: [...].

If events is an empty list, can return 204 No Content or 200 with an empty array.

next/2 for single‐event fetch:

Accepts same query params.

Calls MyApp.KillmailStore.fetch_one_event(client_id, system_list).

If :empty, returns 204 No Content.

If {:ok, {event_id, sys_id, km}}, returns 200 with JSON %{event_id: event_id, system_id: sys_id, killmail: km}.

Add routes in lib/my_app_web/router.ex under an API scope:

elixir
Copy
Edit
scope "/api", MyAppWeb do
get "/killfeed", KillfeedController, :poll
get "/killfeed/next", KillfeedController, :next
end
In any place where raw killmail ingestion happens (e.g. inside your existing zKillBoard listener or ESI fetcher), replace the old RedisQ insertion with a call to MyApp.KillmailStore.insert_event(system_id, killmail_map) so that each new killmail both goes into ETS and is broadcast over PubSub.

Write a client example (in doc/killfeed_example.md) showing how to:

Open a Phoenix Channel or PubSub subscription to "system:<system_id>", using Phoenix.PubSub.subscribe(MyApp.PubSub, "system:30000142") to receive {:new_killmail, 30000142, killmail} messages in real time.

If the client disconnects or starts fresh, call GET /api/killfeed?client_id=<id>&systems[]=30000142 to backfill any missed events.

After backfill, resume listening on PubSub for real‐time updates.

Add tests under test/my_app/killmail_store_test.exs that:

Start MyApp.KillmailStore in isolation.

Call insert_event/2 three times with the same system_id and different dummy killmail maps.

Call fetch_for_client("test-client", [same_system_id]) and assert you get a list of all three events, each with increasing event_id.

Call fetch_for_client("test-client", [same_system_id]) again and assert you get an empty list (since offsets have been updated).

Insert one more killmail, then call fetch_one_event("test-client", [sys_id]) and assert it returns only that single new event, and next call returns :empty.

Create two different clients with overlapping systems, insert multiple events across two systems, and assert each client’s offsets are tracked independently.

Simulate “garbage collection” by inserting events with low IDs and high IDs, artificially setting multiple client offsets to a high minimum, then call the internal GC function via GenServer.cast/2 and verify ETS rows with event_id <= min_offset are gone.

Add documentation in README.md under a section “Killfeed API” that explains:

The two HTTP endpoints (/api/killfeed and /api/killfeed/next), their query parameters, and example responses.

How to subscribe to PubSub topics ("system:<system_id>") for real‐time updates.

The expected behavior: clients always call back to fetch missed events if they dropped the socket, then resume real‐time.

(Optional) If you need to persist across restarts, replace the ETS tables with Mnesia tables following the same schema:

Create a Mnesia schema with tables :killmail_events (disc_copies, ordered by :event_id), :client_offsets (disc_copies), and :counters (disc_copies).

In MyApp.KillmailStore.init/1, call :mnesia.create_table/2 for each table if not exists and wait for the schema.

Swap all :ets.\* calls to :mnesia.transaction(fn -> … end) + :mnesia.read, :mnesia.write, :mnesia.select as appropriate.

Verify that after a node restart, both stored events and per‐client offsets survive.
