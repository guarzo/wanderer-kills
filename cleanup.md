# Cache Migration Cleanup Tasks

## Core Migration Tasks

- [ ] **Refactor ESI fetchers** - Refactor ESI fetchers (character_fetcher.ex, killmail_fetcher.ex, type_fetcher.ex) and WandererKills.ESI.Client to use a shared DataFetcher pipeline or the HttpClient behaviour directly, deleting bespoke fetcher modules if their logic is subsumed by a generic solution.

- [ ] **Remove manual cleanup scheduler** - Remove the manual cleanup scheduler and `cleanup_expired_entries/0` family of functions: delete the scheduled GenServer invocation, supporting helper functions, and their tests, relying instead on Cachex's built-in TTL eviction.

- [ ] **Eliminate cache stats ETS table** - Eliminate the `:cache_stats` ETS table and custom stats code: implement `Cachex.handle_event/2` callbacks or Telemetry handlers to capture hits/misses, and remove all ETS-based statistics modules and tests.

- [ ] **Audit remaining ETS calls** - Audit the entire codebase for any remaining direct ETS calls (`:ets.insert`, `:ets.lookup`, etc.) or manual caching logic, and refactor them to use the new Cachex-based wrappers.

- [ ] **Write integration tests** - Write integration tests to validate the Cachex migration preserves behavior: cover cache hits, misses, TTL expirations, and fallback functions for critical modules like ESI fetchers and ShipType updaters.

## KillStore Migration Strategy

The current `WandererKills.Killmails.Store` GenServer is complex and still relies on ETS tables for killmail storage and pattern matching queries. Here's the recommended approach to simplify it while keeping the performance benefits of ETS for pattern queries.

### 1. Keep KillStore on ETS, but hide it behind a clean API

Because you need to do pattern-match queries (e.g. "give me all kills for system X"), ETS is by far the simplest and most performant solution. But you don't need a sprawling GenServer for it—just a tiny module that:

- Creates a named ETS table at application start
- Exposes only four core functions
- Uses match specs under the covers for efficient queries

**Core API:**

```elixir
put(kill_id, system_id, kill_data)
get(kill_id)             # → {:ok, kill_data} | :error
list_by_system(system_id) # → [kill_data, …]
delete(kill_id)          # if you need removals
```

**Implementation:**

```elixir
defmodule WandererKills.KillStore do
  @table :killmail_store

  # Called at app start—no GenServer needed
  def init_table! do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
  end

  def put(kill_id, system_id, kill_data) do
    :ets.insert(@table, {kill_id, system_id, kill_data})
  end

  def get(kill_id) do
    case :ets.lookup(@table, kill_id) do
      [{^kill_id, _sys, data}] -> {:ok, data}
      [] -> :error
    end
  end

  def list_by_system(system_id) do
    # match spec: {key, system_id, value} → return value
    ms = [{{:"$1", system_id, :"$2"}, [], [:"$2"]}]
    :ets.select(@table, ms)
  end

  def delete(kill_id), do: :ets.delete(@table, kill_id)
end
```

**Application Integration:**

```elixir
def start(_type, _args) do
  WandererKills.KillStore.init_table!()
  children = [
    # ... your other Cachex children here ...
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

**Benefits:**

- No GenServer boilerplate for ETS
- Clear, focused API for all killmail operations
- O(1) inserts/lookup and pattern queries via `:ets.select`

### 2. Collapse all other ETS-based caches into Cachex

For everything else—active-systems, fetch timestamps, per-resource TTLs—you can now confidently rip out your Core.Cache GenServer and the ETS tables it owns, and replace them with:

```elixir
# in your supervision tree
{Cachex, name: :systems_cache, ttl: {:timer.minutes(10), :timer.minutes(15)}},
{Cachex, name: :esi_cache,    ttl: {:timer.seconds(config(:esi_ttl)), :timer.minutes(30)}},
# etc.
```

Then each domain just does:

```elixir
Cachex.fetch!(:systems_cache, system_id, fn ->
  # fallback: load from DB or remote
end)
```

That leaves killmail storage as your only ETS dependency, which is fine given its query patterns.

### 3. Naming & Organization

- **Module name:** `WandererKills.KillStore` (or `Killmail.Store`)
- **Supervisor:** no `child_spec` needed for ETS tables—just init in `start/2`
- **Remove:** any other ETS tables (in Core.Cache or elsewhere)
- **Document:** in a single `lib/wanderer_kills/kill_store.ex` file so it's obvious why ETS remains

### Summary of Implementation Steps

1. **Extract KillStore logic** into the tiny KillStore module above
2. **Wire `init_table!/0`** into your `Application.start/2`
3. **Delete old GenServer/ETS caches** in `WandererKills.Core.Cache`
4. **Replace with Cachex children** and `Cachex.fetch!/3` calls
5. **Verify migration** - ensure every other cache has been removed and tests still pass

**End Result:** One unified cache layer (Cachex) plus one focused ETS-backed killmail store for pattern-matching queries.



---- more stuff ----

2. Configuration Sprawl
WandererKills.Core.Config defines dozens of nearly identical getters (port/0, cache_ttl/1, retry_http_max_retries/0, parser_cutoff_seconds/0, …). This is harder to maintain and discover.
Recommendation:

Group related settings under maps or structs (e.g. config :wanderer_kills, cache: %{killmails_ttl: …}, then Config.cache().killmails_ttl).

Use a small number of generic accessors (e.g. Config.get([:cache, :killmails_ttl])) with compile-time validation.

3. Inconsistent Naming & API Surface
Across modules you have:

get_system_fetch_timestamp/1 vs set_fetch_timestamp/2 vs get_fetch_timestamp/1

add_active_system/1 vs Cache.add_active/1 vs Cache.Systems.add_active/1

get_killmails_for_system/1 vs get_killmails/1

This fragmentation makes it hard to know which function to call.
Recommendation:

Adopt a single canonical naming per domain operation. For example, in Cache.Systems, have exactly fetch_timestamp/1, mark_active/1, list_active/0, etc.

Deprecate or remove redundant aliases.

4. Error-Handling via Rescue/Catch
A number of modules use broad try/rescue or catch to handle both expected and unexpected failures (e.g. in Cachex.fetch fallbacks, in BatchProcessor.await_tasks). While resilient, this can swallow bugs and make debugging harder.
Recommendation:

Restrict rescues to known exception types.

Let truly unexpected crashes bubble up (or be caught by supervisors) so you can observe stack traces.

Consider wrapping only the fallback function in Cachex.fetch rather than the entire case.

5. BatchProcessor Complexity
WandererKills.Core.BatchProcessor provides three overlapping APIs (process_parallel, process_sequential, process_batched) plus await_tasks. While flexible, this may be more than you need.
Recommendation:

Trim to a core abstraction (e.g. only process_parallel/3 and a simple sequential fallback).

Document default timeouts and concurrency limits in one place rather than spreading through Config.

6. Test Coverage & Mocks
Your test suite includes Mox mocks for HTTP, ESI, ZKB, and test-specific cache names. That’s excellent. Make sure:

You have tests covering the edge cases around TTL expiration and “active systems” cleanup.

You exercise both happy and failure paths in Cachex.fetch fallback logic.

