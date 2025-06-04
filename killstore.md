# MyApp.KillmailStore Implementation Guide

This document outlines the implementation of a GenServer-based killmail storage and distribution system using ETS tables, Phoenix PubSub, and HTTP endpoints.

## Core GenServer Module

### Create the GenServer Module

Create a new GenServer module `MyApp.KillmailStore` that implements the following initialization:

#### `init/1` Implementation

On `init/1`, the module should:

1. Create an ETS table named `:killmail_events` of type `:ordered_set`, public, named table
2. Create an ETS table named `:client_offsets` of type `:set`, public, named table
3. Create an ETS table named `:counters` of type `:set`, public, named table, and insert `{:killmail_seq, 0}`
4. Return `{:ok, %{}}` as its initial state

## Public API Functions

### 1. `insert_event/2`

Implement a public function:

```elixir
insert_event(system_id :: integer(), killmail_map :: map()) :: :ok
```

**Behavior:**

- Calls `GenServer.call(__MODULE__, {:insert, system_id, killmail_map})`

**GenServer Handler:** `handle_call({:insert, system_id, killmail_map}, _from, state)`

1. Read the current counter from `:counters` (`:killmail_seq`)
2. Increment it by 1 and write it back as the new `:killmail_seq`
3. Insert `{new_seq, system_id, killmail_map}` into ETS table `:killmail_events`
4. Broadcast via `Phoenix.PubSub.broadcast!/3` on topic `"system:#{system_id}"` with message `{:new_killmail, system_id, killmail_map}`
5. Reply `{:reply, :ok, state}`

### 2. `fetch_for_client/2`

Implement a public function:

```elixir
fetch_for_client(client_id :: String.t(), system_ids :: [integer()]) :: {:ok, [{integer(), integer(), map()}]}
```

**Behavior:**

- Calls `GenServer.call(__MODULE__, {:fetch, client_id, system_ids})`

**GenServer Handler:** `handle_call({:fetch, client_id, system_ids}, _from, state)`

1. Look up ETS `:client_offsets` for key `client_id`. If none, use `%{}` as offsets
2. Iterate over every ETS row in `:killmail_events` (via `:ets.foldl/3`) to collect `[{event_id, sys_id, km} | acc]` where:
   - `sys_id` is in `system_ids`
   - `event_id > offset_for(sys_id, offsets)`
3. Sort the resulting list ascending by `event_id`
4. Build `updated_offsets` by taking the max `event_id` per `sys_id` in that list and merging into the client's offsets map
5. Write `:ets.insert(:client_offsets, {client_id, updated_offsets})`
6. Reply `{:reply, {:ok, sorted_events}, state}`

### 3. `fetch_one_event/2`

Implement a public function:

```elixir
fetch_one_event(client_id :: String.t(), system_ids :: [integer()]) :: {:ok, {event_id :: integer(), system_id :: integer(), killmail_map :: map()}} | :empty
```

**Behavior:**

- Calls `GenServer.call(__MODULE__, {:fetch_one, client_id, system_ids})`

**GenServer Handler:** `handle_call({:fetch_one, client_id, system_ids}, _from, state)`

1. Read ETS `:client_offsets` for `client_id` or default to `%{}`
2. Use `:ets.foldl/3` to scan every `{event_id, sys_id, km}` in `:killmail_events`
3. Keep only the single tuple with the smallest `event_id` such that:
   - `sys_id` in `system_ids`
   - `event_id > offset_for(sys_id)`
4. If no matching row is found, reply `{:reply, :empty, state}`
5. Otherwise, update the offset for that single `sys_id` in ETS `:client_offsets` to the returned `event_id`
6. Reply `{:reply, {:ok, {event_id, sys_id, km}}, state}`

## Garbage Collection

### Periodic Cleanup Process

Add a periodic "garbage-collection" process (`GenServer.cast/2`) inside `MyApp.KillmailStore` that:

- Runs every 60 seconds (via `Process.send_after/3`)
- Performs the following operations:

1. Read all client-offset maps from `:client_offsets` (via `:ets.tab2list/1`)
2. Merge them to find the global minimum `min_offset` across all systems
3. Delete every ETS row in `:killmail_events` with `event_id <= min_offset` (use `:ets.select_delete/2` or `:ets.foldl/3` + `:ets.delete_object/2`)
4. Schedule itself to run again in 60,000 ms

## Application Setup

### Supervision Tree

Register `MyApp.KillmailStore` in the application supervision tree (e.g., in `lib/my_app/application.ex`):

```elixir
children = [
  MyApp.KillmailStore,
  {Phoenix.PubSub, name: MyApp.PubSub},
  # … other children …
]
```

### Dependencies

Ensure `:phoenix_pubsub` is listed as an application dependency in `mix.exs`, and verify `config/config.exs` contains:

```elixir
config :my_app, MyApp.PubSub,
  adapter: Phoenix.PubSub.PG2
```

## Phoenix Controller

### Create KillfeedController

Create a Phoenix Controller `MyAppWeb.KillfeedController` with two actions:

#### 1. `poll/2` - Batch Fetch

- **Purpose:** Batch fetch for multiple events
- **Route:** `GET /killfeed?client_id=foo&systems[]=30000142&systems[]=30000143`
- **Behavior:**
  - Accepts `client_id` and `systems` as query params
  - Calls `MyApp.KillmailStore.fetch_for_client(client_id, system_list)`
  - Returns 200 with JSON `events: [...]`
  - If events is empty, can return 204 No Content or 200 with an empty array

#### 2. `next/2` - Single Event Fetch

- **Purpose:** Single-event fetch
- **Route:** Same query params as `poll/2`
- **Behavior:**
  - Calls `MyApp.KillmailStore.fetch_one_event(client_id, system_list)`
  - If `:empty`, returns 204 No Content
  - If `{:ok, {event_id, sys_id, km}}`, returns 200 with JSON:
    ```json
    {
      "event_id": event_id,
      "system_id": sys_id,
      "killmail": km
    }
    ```

### Router Configuration

Add routes in `lib/my_app_web/router.ex` under an API scope:

```elixir
scope "/api", MyAppWeb do
  get "/killfeed", KillfeedController, :poll
  get "/killfeed/next", KillfeedController, :next
end
```

## Integration

### Killmail Ingestion

In any place where raw killmail ingestion happens (e.g., inside your existing zKillBoard listener or ESI fetcher):

- Replace the old RedisQ insertion with a call to `MyApp.KillmailStore.insert_event(system_id, killmail_map)`
- This ensures each new killmail both goes into ETS and is broadcast over PubSub

## Client Usage

### Example Implementation

Write a client example (in `doc/killfeed_example.md`) showing how to:

1. **Real-time Subscription:**

   - Open a Phoenix Channel or PubSub subscription to `"system:<system_id>"`
   - Use `Phoenix.PubSub.subscribe(MyApp.PubSub, "system:30000142")` to receive `{:new_killmail, 30000142, killmail}` messages in real time

2. **Backfill Process:**
   - If the client disconnects or starts fresh, call `GET /api/killfeed?client_id=<id>&systems[]=30000142` to backfill any missed events
   - After backfill, resume listening on PubSub for real-time updates

## Testing

### Test Suite

Add tests under `test/my_app/killmail_store_test.exs` that:

1. **Basic Functionality:**

   - Start `MyApp.KillmailStore` in isolation
   - Call `insert_event/2` three times with the same `system_id` and different dummy killmail maps
   - Call `fetch_for_client("test-client", [same_system_id])` and assert you get a list of all three events, each with increasing `event_id`

2. **Offset Tracking:**

   - Call `fetch_for_client("test-client", [same_system_id])` again and assert you get an empty list (since offsets have been updated)
   - Insert one more killmail, then call `fetch_one_event("test-client", [sys_id])` and assert it returns only that single new event
   - Next call should return `:empty`

3. **Multi-client Support:**

   - Create two different clients with overlapping systems
   - Insert multiple events across two systems
   - Assert each client's offsets are tracked independently

4. **Garbage Collection:**
   - Insert events with low IDs and high IDs
   - Artificially set multiple client offsets to a high minimum
   - Call the internal GC function via `GenServer.cast/2`
   - Verify ETS rows with `event_id <= min_offset` are gone

## Documentation

### README.md Section

Add documentation in `README.md` under a section "Killfeed API" that explains:

1. **HTTP Endpoints:**

   - The two HTTP endpoints (`/api/killfeed` and `/api/killfeed/next`)
   - Their query parameters and example responses

2. **Real-time Updates:**

   - How to subscribe to PubSub topics (`"system:<system_id>"`) for real-time updates

3. **Expected Behavior:**
   - Clients always call back to fetch missed events if they dropped the socket
   - Then resume real-time updates

## Optional: Mnesia Persistence

### Database Persistence

If you need to persist across restarts, replace the ETS tables with Mnesia tables:

1. **Schema Creation:**

   - Create a Mnesia schema with tables:
     - `:killmail_events` (disc_copies, ordered by `:event_id`)
     - `:client_offsets` (disc_copies)
     - `:counters` (disc_copies)

2. **Initialization:**

   - In `MyApp.KillmailStore.init/1`, call `:mnesia.create_table/2` for each table if not exists
   - Wait for the schema

3. **Data Operations:**

   - Swap all `:ets.*` calls to `:mnesia.transaction(fn -> … end)` + `:mnesia.read`, `:mnesia.write`, `:mnesia.select` as appropriate

4. **Verification:**
   - Verify that after a node restart, both stored events and per-client offsets survive
