# Elixir Codebase Cleanup Recommendations

Based on the merged codebase analysis, here are comprehensive recommendations to improve organization, remove duplication and legacy code, adopt more idiomatic Elixir patterns, and tighten up naming conventions.

## 1. Reorganize Modules into Clear, Domain-Driven Contexts

### Current Issues

- Modules are grouped by technical layers rather than business domains
- Related functionality is scattered across different directories

### Recommendations

**Group by business domain:**

- **Killmail handling**: Move all killmail-related modules (`KillmailStore`, `Killmails.Parser`, `Killmails.Enricher`, etc.) under:

  ```
  lib/wanderer_kills/killmails/
  ```

  Namespace: `WandererKills.Killmails.*`

- **Ship type logic**: Consolidate under:

  ```
  lib/wanderer_kills/ship_types/
  ```

  Include: `ShipTypeUpdater`, `ShipTypeInfo`, `ShipTypeConstants`, plus CSV vs. ESI sources

- **ESI-specific modules**: Place under:

  ```
  lib/wanderer_kills/esi/
  ```

  Include: `WandererKills.ESI.Client`, `WandererKills.ESI.Data.*`

- **Real-time streaming**: Combine RedisQ, preloader, supervisor into:

  ```
  lib/wanderer_kills/streaming/
  ```

  or

  ```
  lib/wanderer_kills/preloader/
  ```

- **Eliminate generic `Shared` folder**: Rename or relocate helpers like:

  - `lib/wanderer_kills/shared/CSV.ex`
  - `shared/batch_processor.ex`
  - `shared/circuit_breaker.ex`

  Move into contexts that consume them or into `shared/utils` if truly application-wide.

### Benefits

- New maintainers can immediately find "all killmail behavior here" or "all ship type behavior here"
- Reduces cognitive overhead when navigating the codebase

---

## 2. Remove Duplicated CSV and Parsing Utilities

### Current Duplication

- `lib/wanderer_kills/shared/csv.ex` (with `parse_ship_group/1` and `parse_ship_type/1`)
- `lib/wanderer_kills/data/sources/csv_source.ex` (invokes `CSV.read_file/2` and `CSV.parse_ship_type/1`/`parse_ship_group/1`)

### Solution

1. **Consolidate all CSV parsing logic** into a single module:

   ```elixir
   WandererKills.ShipTypes.CSVHelpers
   # or
   WandererKills.ShipTypes.CSVHelpers
   ```

2. **Delete duplicate variants** - ensure exactly one set of:

   - `parse_ship_type/1`
   - `parse_ship_group/1` functions

3. **HTTP utilities cleanup**: `RequestUtils`, `ClientUtil`, `Util` under `lib/wanderer_kills/http/` appear to overlap
   - Consolidate into single `WandererKills.HTTP.Utils` module
   - Remove extra modules that replicate functionality

---

## 3. Prune Legacy Compatibility Code

### Target Areas

**RedisQ Legacy Format** ⚠️ **REQUIRES VALIDATION**:

**Found in `lib/wanderer_kills/external/zkb/redisq.ex` lines 146-165:**

```elixir
# New‐format: "package" → %{ "killID" => _, "killmail" => killmail, "zkb" => zkb }
{:ok, %{body: %{"package" => %{"killID" => _id, "killmail" => killmail, "zkb" => zkb}}}} ->
  Logger.info("[RedisQ] New‐format killmail received.")
  process_kill(killmail, zkb)

# Alternate new‐format (sometimes `killID` is absent, but `killmail`+`zkb` exist)
{:ok, %{body: %{"package" => %{"killmail" => killmail, "zkb" => zkb}}}} ->
  Logger.info("[RedisQ] New‐format killmail (no killID) received.")
  process_kill(killmail, zkb)

# Legacy format: { "killID" => id, "zkb" => zkb }
{:ok, %{body: %{"killID" => id, "zkb" => zkb}}} ->
  Logger.info("[RedisQ] Legacy‐format killmail ID=#{id}.  Fetching full payload…")
  process_legacy_kill(id, zkb)
```

**Investigation Required:**

- **RedisQ Stream API** (`listen.php`) might return minimal format requiring ESI fetch
- **ZKB REST API** (`/api/killmail/`) might return full killmail data
- **User's concern is valid** - need to validate if this is truly "legacy" vs different endpoints

**Recommended Actions:**

1. **Add format tracking telemetry** to `do_poll/1` function
2. **Monitor for 1-2 weeks** to see which formats are actually received
3. **Only remove after confirmation** that minimal format is truly unused
4. **Consider adding configuration flag** to disable legacy handling during transition

**Deprecated ESI Endpoints**:

- Audit code paths supporting old ESI endpoints or deprecated payload shapes
- Remove guards around old response fields in RedisQ
- Verify you're not querying both `/universe/types/{type_id}` and older endpoints

---

## 4. Rename "Shared" or "Infrastructure" to Descriptive Modules

### Current State

`lib/wanderer_kills/shared/` contains cross-cutting concerns

### Recommended Approach

**Option A: Infrastructure namespace**

```elixir
WandererKills.Infrastructure.Clock
WandererKills.Infrastructure.CSV
WandererKills.Infrastructure.Enricher
```

**Option B: Utils namespace**

```elixir
WandererKills.Utils.Clock
WandererKills.Utils.CSV
WandererKills.Utils.Enricher
```

### Benefits

- Clear meaning instead of ambiguous "Shared" namespace
- Easier to understand module responsibilities

---

## 5. Adopt Idiomatic OTP/Erlang Patterns

### Supervisor Improvements

**Current pattern in `WandererKills.Preloader.Supervisor`:**

```elixir
# Avoid manual map building
children = [%{id: ..., start: {...}, ...}]
```

**Recommended idiomatic pattern:**

```elixir
children = [
  WandererKills.Preloader.Worker,
  {WandererKills.External.ZKB.RedisQ,
   restart: :permanent,
   timeout: :timer.seconds(30)}
]
Supervisor.init(children, strategy: :one_for_one)
```

### Additional OTP Improvements

- **Child specifications**: Use `YourModule.child_spec/1` rather than raw maps
- **ETS tables**: Move logic out of `init/1` into separate "ETS supervisor" or dedicated module
- **Leaner init callbacks**: Keep `init/1` focused and minimal

---

## 6. Ensure Consistent Naming Conventions

### Module Names (PascalCase)

**Current issues and fixes:**

- `WandererKills.Data.Behaviours.ShipTypeSource` → move to `lib/wanderer_kills/ship_types/source.ex`

  - Module: `WandererKills.ShipTypes.Source`

- `WandererKills.Fetcher` vs. `WandererKills.Fetcher.Shared`:

  - Rename to `WandererKills.Fetcher.Unified`
  - Or split into `WandererKills.KillmailFetcher` and `WandererKills.SystemFetcher`

- **Avoid overloading**: If module is exclusively used by "fetchers":
  - Use `Fetcher.BatchOperations`
  - Move to `lib/wanderer_kills/fetcher/batch_operations.ex`

### Function Names (snake_case)

- Ensure all function names use `snake_case`
- Translate JSON keys to `snake_case` early in parsing
- Use consistent atom/string patterns (e.g., `killmail_id` vs `"killID"`)

### Constants Consolidation

**Current duplication:**

- `lib/wanderer_kills/data/` has Constants modules
- `lib/wanderer_kills/shared/constants.ex` exists

**Solution:**

- Consolidate into single `WandererKills.Constants` or `WandererKills.Config.Constants`

---

## 7. Remove Overlapping HTTP Client Behavior Definitions

### Current Overlap

- `WandererKills.Http.ClientBehaviour` (in `http/client_behaviour.ex`)
- `WandererKills.Http.Client` implementing nearly identical callbacks

### Solutions

**If no other HTTP implementation planned:**

- Drop `ClientBehaviour` module altogether
- Treat `Http.Client` as single source of truth

**If mocking needed for tests:**

- Keep behaviour but remove duplicate specs in `client_util.ex` or `request_utils.ex`
- Ensure "HTTP util" modules only contain orthogonal logic (URL formatting, headers)

---

## 8. Consolidate Configuration and Remove Hard-coded Values

### Current Issues

- Many modules use `Application.fetch_env!` with inline key lookups
- Magic numbers scattered throughout code (e.g., ship group IDs `[6,7,9,11,16,17,23]`)

### Recommended Approach

**Create centralized config module:**

```elixir
# Instead of manual config lookups
Config.redisq(:fast_interval_ms)

# Single source for constants
ShipTypeConstants.ship_group_ids()
```

**Benefits:**

- Normalized config shapes
- Single point of configuration management
- Easier testing and maintenance

---

## 9. Eliminate "Mixed Responsibility" Modules

### Problem: `WandererKills.Fetcher.Shared`

- Currently ~500 lines doing everything:
  - Fetching from ZKB
  - Caching
  - Parsing
  - Enriching
  - Telemetry

### Solution: Break into Single-Responsibility Modules

```elixir
# Raw ZKB API calls and parsing
WandererKills.Fetcher.ZkbFetch

# Caching concerns: updating ETS, PubSub
WandererKills.CacheHouseKeeper

# Already separate
WandererKills.Killmails.Enricher

# Thin orchestrator ties them together
WandererKills.Fetcher.Orchestrator
```

### Benefits

- Easier testing
- Clearer reasoning about each component
- Simpler maintenance

---

## 10. Standardize Error Tuples and Remove Redundant Wrappers

### Current Approach

Frequent wrapping as:

- `{:error, reason}`
- `{:error, {:cache, reason}}`
- `{:error, {:http, reason}}`

### Recommended Solutions

**Option A: Consistent `with` patterns**

```elixir
with {:ok, val} <- ... do
  # Handle success
else
  error -> translate_error(error)
end
```

**Option B: Custom Error struct**

```elixir
%WandererKills.Error{context: :cache, reason: reason}
```

### Additional Guidelines

- Remove "catch-all" rescue clauses that swallow exceptions
- Use `rescue` only when specifically needed
- Let top-level functions translate nested error tuples

---

## 11. Validate and Remove Obsolete Test Support Code

### Test Configuration

- `config/test.exs` disables `start_preloader: false`
- If no tests need preloader, remove startup logic references

### Cleanup Actions

1. **Guard preloader startup:**

   ```elixir
   if Application.get_env(:wanderer_kills, :start_preloader) do
     # Add to supervision tree
   end
   ```

2. **Remove unused mocks:**
   - `WandererKills.Zkb.Client.Mock` (if unused)
   - Corresponding test files (e.g., `external/zkb_fetcher_test.exs`)

---

## 12. Streamline Telemetry and Observability Modules

### Current Structure

```
lib/wanderer_kills/observability/
├── behaviours/health_check.ex
├── health_checks/
├── monitoring.ex
└── telemetry.ex
```

### Recommendations

**If not using multiple health checks:**

- Collapse into single `Observability.Health` context
- Remove unused behaviour definitions

**Telemetry cleanup:**

- Instrument only actual boundaries (HTTP, ETS, fetch processes)
- Remove duplicate events (e.g., `"fetch_system_start"` vs `"telemetry.fetch_system_start"`)
- Consider renaming `WandererKills.Observability.Telemetry` to `WandererKills.Instrumentation`

---

## 13. Remove Deep Nesting of Configuration Sections

### Current Deep Nesting

```elixir
config :wanderer_kills, retry: %{
  http: %{max_retries: 3, base_delay: 1000},
  redisq: %{max_retries: 5, base_delay: 500}
}
```

### Recommended Flattening

```elixir
config :wanderer_kills, :retry_http, %{max_retries: 3, base_delay: 1000}
config :wanderer_kills, :retry_redisq, %{max_retries: 5, base_delay: 500}
```

### Benefits

- Simpler access: `Application.get_env(:wanderer_kills, :retry_http)`
- No need to dig into nested keys
- Clearer configuration structure

---

## 14. Ensure Supervisors Honor Configuration Flags

### Application Supervisor Improvements

**Instead of unconditional preloader:**

```elixir
children = [
  # ... other children
] ++ if(Application.get_env(:wanderer_kills, :start_preloader, true),
       do: [WandererKills.Preloader.Supervisor],
       else: [])
```

### Configuration Function Standardization

**Current inconsistency:**

- `get_config(:idle_interval_ms)` in RedisQ
- Mixed string keys and atom keys

**Recommended approach:**

```elixir
# Consistent function naming
Config.redisq(:idle_interval_ms)
# or
Config.redisq_idle_interval_ms()
```

**Ensure alignment:**

- Config keys (`:base_url`, `:fast_interval_ms`) align exactly with module functions
- Prevent runtime errors from key mismatches

---

## Implementation Action Items

### Phase 1: Structure and Organization

1. **Refactor directory structure** into context folders:

   - `killmails/`
   - `ship_types/`
   - `esi/`
   - `streaming/`
   - `http/`
   - `observability/`

2. **Merge duplicate utilities**:
   - All CSV parsing into single module
   - All HTTP utility logic consolidation

### Phase 2: Code Cleanup

3. **Delete legacy code**:

   - Legacy-only branches in RedisQ -- validate this is actually legacy, and not the difference between the api path and the redisq path?????
   - Unused ESI endpoints
   - Obsolete test support code

4. **Rename for clarity**:
   - `shared/` → `infrastructure/` or `utils/`
   - Update all module names accordingly

### Phase 3: Pattern Adoption

5. **Simplify OTP components**:

   - Use built-in child specs
   - Lean `init/1` callbacks
   - Proper supervisor patterns

6. **Standardize naming**:
   - Module and function consistency
   - Eliminate Constants confusion
   - Unified config approach

### Expected Outcomes

- **Reduced duplication**: Single source of truth for common functionality
- **Clearer architecture**: Domain-driven organization
- **More "Elixir-ish" feel**: Idiomatic OTP and naming patterns
- **Easier maintenance**: Simplified navigation and understanding
- **Better testability**: Single-responsibility modules
