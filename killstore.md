# WandererKills.KillmailStore Implementation Guide

This document outlines the implementation of a GenServer-based killmail storage and distribution system using ETS tables, Phoenix PubSub, and HTTP endpoints for the WandererKills project.

## Project Context & Integration Points

**Current Application Structure:**

- **Project Name:** `wanderer_kills`
- **Main Module:** `WandererKills`
- **HTTP API:** Uses Plug.Router in `WandererKills.Web.Api`
- **Application:** Supervised by `WandererKills.Application`
- **Killmail Processing:** Currently handled by `WandererKills.Parser` and ingested via `WandererKills.Preloader.RedisQ`

## Dependencies Updates

**Add to `mix.exs`:**

```elixir
defp deps do
  [
    # ... existing deps ...
    {:phoenix_pubsub, "~> 2.1"},  # Add this line
    # ... rest of deps ...
  ]
end
```

## Core GenServer Module

### Create the GenServer Module

Create a new GenServer module `WandererKills.KillmailStore` that implements the following initialization:

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

Add a periodic "garbage-collection" process (`GenServer.cast/2`) inside `WandererKills.KillmailStore` that:

- Runs every 60 seconds (via `Process.send_after/3`)
- Performs the following operations:

1. Read all client-offset maps from `:client_offsets` (via `:ets.tab2list/1`)
2. Merge them to find the global minimum `min_offset` across all systems
3. Delete every ETS row in `:killmail_events` with `event_id <= min_offset` (use `:ets.select_delete/2` or `:ets.foldl/3` + `:ets.delete_object/2`)
4. Schedule itself to run again in 60,000 ms

## Application Setup

### Supervision Tree

Register `WandererKills.KillmailStore` in the application supervision tree in `lib/wanderer_kills/application.ex`:

```elixir
defp base_children do
  [
    {Task.Supervisor, name: WandererKills.TaskSupervisor},
    {Phoenix.PubSub, name: WandererKills.PubSub},  # Add this
    WandererKills.KillmailStore,                    # Add this
    WandererKills.Cache.Supervisor,
    # ... rest of existing children ...
  ]
end
```

### Dependencies & Configuration

Update `config/config.exs`:

```elixir
# Add Phoenix PubSub configuration
config :wanderer_kills, WandererKills.PubSub,
  adapter: Phoenix.PubSub.PG2

# Add killmail store configuration
config :wanderer_kills,
  # ... existing config ...
  killmail_store: %{
    gc_interval_ms: 60_000,
    max_events_per_system: 10_000
  }
```

## Parser Integration

### Integration Points

**In `lib/wanderer_kills/parser.ex`** - Modify `process_killmail/3`:

```elixir
defp process_killmail(full, zkb, cutoff) do
  with {:ok, merged} <- Core.merge_killmail_data(full, %{"zkb" => zkb}),
       {:ok, built} <- Core.build_kill_data(merged, cutoff),
       {:ok, enriched} <- enrich_killmail(built) do

    # INTEGRATION POINT: Add to KillmailStore
    system_id = enriched["solar_system_id"] || enriched["system_id"]
    :ok = WandererKills.KillmailStore.insert_event(system_id, enriched)

    Logger.info("Successfully enriched and stored killmail", %{
      killmail_id: full["killmail_id"],
      system_id: system_id,
      operation: :process_killmail,
      status: :success
    })

    {:ok, enriched}
  else
    # ... existing error handling ...
  end
end
```

**Data Structure Considerations:**

- Normalize system_id field: `killmail["solar_system_id"] || killmail["system_id"]`
- Preserve full killmail structure as received from parser
- Handle varying field names (`killmail_id` vs `killID`)

## HTTP API Integration

### Update Existing API Router

**Update `lib/wanderer_kills/web/api.ex`:**

Add new routes before the catch-all `match _ do`:

```elixir
# Killfeed endpoints
get "/api/killfeed" do
  WandererKills.Web.Api.KillfeedController.poll(conn, conn.query_params)
end

get "/api/killfeed/next" do
  WandererKills.Web.Api.KillfeedController.next(conn, conn.query_params)
end
```

### Create KillfeedController

Create `lib/wanderer_kills/web/api/killfeed_controller.ex` with two actions:

#### 1. `poll/2` - Batch Fetch

- **Purpose:** Batch fetch for multiple events
- **Route:** `GET /api/killfeed?client_id=foo&systems[]=30000142&systems[]=30000143`
- **Behavior:**
  - Accepts `client_id` and `systems` as query params
  - Calls `WandererKills.KillmailStore.fetch_for_client(client_id, system_list)`
  - Returns 200 with JSON `events: [...]`
  - If events is empty, can return 204 No Content or 200 with an empty array

#### 2. `next/2` - Single Event Fetch

- **Purpose:** Single-event fetch
- **Route:** Same query params as `poll/2`
- **Behavior:**
  - Calls `WandererKills.KillmailStore.fetch_one_event(client_id, system_list)`
  - If `:empty`, returns 204 No Content
  - If `{:ok, {event_id, sys_id, km}}`, returns 200 with JSON:
    ```json
    {
      "event_id": event_id,
      "system_id": sys_id,
      "killmail": km
    }
    ```

## Configuration Enhancements

### Update Config Module

**Update `lib/wanderer_kills/config.ex`:**

```elixir
@doc """
Gets killmail store configuration settings.
"""
@spec killmail_store() :: %{
        gc_interval_ms: integer(),
        max_events_per_system: integer()
      }
def killmail_store do
  config = Application.get_env(:wanderer_kills, :killmail_store, [])

  case config do
    config when is_map(config) ->
      %{
        gc_interval_ms: Map.get(config, :gc_interval_ms, 60_000),
        max_events_per_system: Map.get(config, :max_events_per_system, 10_000)
      }

    config when is_list(config) ->
      %{
        gc_interval_ms: Keyword.get(config, :gc_interval_ms, 60_000),
        max_events_per_system: Keyword.get(config, :max_events_per_system, 10_000)
      }
  end
end
```

## Client Usage

### Example Implementation

Write a client example showing how to:

1. **Real-time Subscription:**

   - Open a Phoenix Channel or PubSub subscription to `"system:<system_id>"`
   - Use `Phoenix.PubSub.subscribe(WandererKills.PubSub, "system:30000142")` to receive `{:new_killmail, 30000142, killmail}` messages in real time

2. **Backfill Process:**
   - If the client disconnects or starts fresh, call `GET /api/killfeed?client_id=<id>&systems[]=30000142` to backfill any missed events
   - After backfill, resume listening on PubSub for real-time updates

## Testing

### Test Suite

Add tests under `test/wanderer_kills/killmail_store_test.exs` following existing patterns from `test/wanderer_kills/api_test.exs`:

1. **Basic Functionality:**

   - Start `WandererKills.KillmailStore` in isolation
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

**Create:** `test/wanderer_kills/web/api/killfeed_controller_test.exs`

## Monitoring Integration

**Integrate with existing telemetry:**

```elixir
# Add to lib/wanderer_kills/infrastructure/telemetry.ex
def count_killmail_store_operations do
  # Count ETS operations, PubSub broadcasts, etc.
end
```

## Migration Considerations

**Backward Compatibility:**

- Existing endpoints (`/killmail/:id`, `/system_killmails/:system_id`, etc.) remain unchanged
- New killfeed endpoints are additive
- No changes to existing cache behavior
- Parser continues to cache killmails as before

**Performance Considerations:**

- ETS tables are in-memory only (as specified)
- Garbage collection every 60 seconds to prevent memory bloat
- Client offset tracking prevents duplicate deliveries
- Integration with existing rate limiting and monitoring

## Implementation Order

1. Add Phoenix PubSub dependency and configuration
2. Create basic KillmailStore GenServer with ETS tables
3. Add integration point in Parser module
4. Create KillfeedController with basic endpoints
5. Add routes to main API module
6. Write comprehensive tests
7. Add telemetry and monitoring
8. Update documentation

## Optional: Mnesia Persistence

### Database Persistence

If you need to persist across restarts, replace the ETS tables with Mnesia tables:

1. **Schema Creation:**

   - Create a Mnesia schema with tables:
     - `:killmail_events` (disc_copies, ordered by `:event_id`)
     - `:client_offsets` (disc_copies)
     - `:counters` (disc_copies)

2. **Initialization:**

   - In `WandererKills.KillmailStore.init/1`, call `:mnesia.create_table/2` for each table if not exists
   - Wait for the schema

3. **Data Operations:**

   - Swap all `:ets.*` calls to `:mnesia.transaction(fn -> … end)` + `:mnesia.read`, `:mnesia.write`, `:mnesia.select` as appropriate

4. **Verification:**
   - Verify that after a node restart, both stored events and per-client offsets survive
