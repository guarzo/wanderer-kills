# WandererKills Codebase Cleanup Recommendations

This document outlines a comprehensive refactoring plan for the WandererKills application to improve code organization, reduce duplication, and align with Elixir/Phoenix conventions.

## 1. Reorganize by Business Domain (High Priority)

### Current State

The codebase is organized by technical layers:

- `lib/wanderer_kills/core/` - Generic utilities (5 modules)
- `lib/wanderer_kills/parser/` - Mixed parsing logic (14 modules)
- `lib/wanderer_kills/cache/` - Cache implementations (4 directories)
- `lib/wanderer_kills/data/` - Data layer concerns (3 directories)

### Recommended Structure

Reorganize into domain-driven contexts:

```
lib/wanderer_kills/
├── killmails/           # Killmail business logic
│   ├── parser.ex        # From parser/killmail_parser.ex
│   ├── enricher.ex      # From parser/killmail_enricher.ex
│   ├── stats.ex         # From parser/killmail_stats.ex
│   └── store.ex         # From killmail_store.ex
├── ship_types/          # Ship type management
│   ├── parser.ex        # From parser/ship_type_parser.ex
│   ├── updater.ex       # From data/ship_type_updater.ex
│   └── info.ex          # From data/ship_type_info.ex
├── systems/             # Solar system data and caching
│   └── cache.ex         # From cache/specialized/system_cache.ex
├── esi/                 # ESI API client (keep existing)
├── zkb/                 # ZKillboard client (keep existing)
└── shared/              # Cross-cutting concerns
    ├── http_client.ex   # From http/
    ├── config.ex        # From core/config.ex
    └── utils/           # General utilities
```

## 2. Eliminate CSV Parsing Duplication (High Priority)

### Current Duplication

CSV parsing logic is duplicated across:

- `parser/csv_util.ex` (186 lines)
- `parser/csv_row_parser.ex` (130 lines)
- `parser/ship_type_parser.ex` (65 lines)
- `data/sources/csv_source.ex` (220 lines)

### Solution

Create unified CSV module consolidating all parsing logic:

```elixir
# lib/wanderer_kills/shared/csv.ex
defmodule WandererKills.Shared.CSV do
  def read_file(path, parser_fn, opts \\ [])
  def parse_row(row, headers)
  def parse_number(value, type, default \\ nil)
  def parse_with_schema(csv_data, schema)
end
```

**Expected Impact**: ~300 lines of duplicate code eliminated

## 3. Simplify Core Module Architecture (Medium Priority)

### Current Problems

The `core/` directory contains over-abstracted modules:

- `config.ex` (168 lines) - Just wraps `Application.get_env/2`
- `batch_processor.ex` (279 lines) - Custom batching logic
- `circuit_breaker.ex` (208 lines) - Custom circuit breaker
- `clock.ex` (230 lines) - Complex time abstraction

### Recommended Changes

1. **Simplify config access** - Remove unnecessary wrapper functions
2. **Evaluate custom implementations** - Consider library alternatives
3. **Move to shared namespace** - Remove "Core" designation

## 4. Streamline Cache Architecture (Medium Priority)

### Current Issues

- Verbose hierarchy: Base → Unified → Specialized
- Single-child supervisor adds no value
- Mixed access patterns (some call Cachex directly)

### Solution

Flatten cache hierarchy and enforce consistent access:

```elixir
# Single cache interface
WandererKills.Cache.get_killmail(id)
WandererKills.Cache.Systems.get_active()
WandererKills.Cache.ESI.get_character(id)
```

## 5. Consolidate Parser Architecture (Medium Priority)

### Current Problems

Parser directory has 14 modules with mixed responsibilities:

- Cache logic in parser directory
- Duplicate statistics modules
- Complex coordination patterns

### Solution

Move domain-specific parsers to appropriate contexts and separate concerns.

## 6. Test Suite Reorganization (Medium Priority)

### Why It Matters

As modules move by domain, test files should mirror that structure so `mix test test/killmails/` works as expected and contributors can locate tests quickly.

### Current Test Issues

- Tests organized by technical layer, not business domain
- Orphaned integration tests at top level
- Mixed unit and integration test types

### Solution

Reorganize tests to match new domain structure:

```
test/
├── killmails/           # All killmail-related tests
│   ├── parser_test.exs
│   ├── enricher_test.exs
│   ├── store_test.exs
│   └── integration_test.exs
├── ship_types/          # Ship type functionality tests
│   ├── parser_test.exs
│   ├── updater_test.exs
│   └── integration_test.exs
├── systems/             # System cache tests
├── integration/         # Cross-domain integration tests
│   ├── api_test.exs
│   └── end_to_end_test.exs
└── support/            # Test helpers
```

**Benefits**: Domain-focused testing, easier test discovery, cleaner CI runs

## 7. Enable and Enforce Linting/Static Analysis in CI (Medium Priority)

### Why It Matters

During re-architecting, consistent code quality prevents introducing new spec mismatches or style divergences.

### Current State

Basic dependencies exist but may not be enforced in CI.

### Solution

Add comprehensive static analysis to CI pipeline:

```elixir
# In mix.exs
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4.3", only: [:dev], runtime: false}
```

**CI Pipeline Steps:**

- `mix format --check-formatted` - Ensure consistent formatting
- `mix credo --strict` - Code quality and style checks
- `mix dialyzer --halt-exit-status` - Type checking for relocated modules

## 8. Prune and Audit Dependencies (Low-Medium Priority)

### Why It Matters

Refactoring is ideal time to remove unused libraries, shortening compile times and reducing surface area.

### Action Items

1. **Audit current dependencies** - Check if all `mix.exs` entries are used
2. **Remove unused packages** - Run `mix deps.unlock --unused`
3. **Evaluate alternatives** - Replace custom implementations with standard libraries

### Current Dependencies to Evaluate

- `:backoff` - Can retry logic be simplified?
- `:uuid` - Is UUID generation actually used?
- Custom circuit breaker - Replace with `:fuse` library?

## 9. Flatten Single-Child Supervisors (Low Priority)

### Why It Matters

Single-child supervisors add unnecessary indirection without providing value.

### Current Issues

- `WandererKills.Cache.Supervisor` only supervises one Cachex instance
- Similar patterns in preloader and batch processor supervisors

### Solution

Update `WandererKills.Application.start/2` to supervise processes directly:

```elixir
# Instead of intermediate supervisors
children = [
  {Cachex, name: :killmails_cache, ttl: config.killmail_ttl},
  {Cachex, name: :systems_cache, ttl: config.system_ttl},
  WandererKills.Preloader.Worker,  # Direct supervision
  # ... other children
]
```

## 10. Align Web Layer (Low Priority)

### Why It Matters

When reorganizing `lib/wanderer_kills/` by domain, ensure `wanderer_kills_web/` references updated context paths.

### Action Items

Update web layer imports to match new structure:

```elixir
# Before
alias WandererKills.Parser.KillmailParser

# After
alias WandererKills.Killmails.Parser
```

**Check Points:**

- Controllers using correct context modules
- Views referencing updated aliases
- Any channels or live views using old paths

## 11. Configuration Environment Consistency (Low Priority)

### Why It Matters

Consolidating `core/config.ex` requires updating environment configuration files to prevent missing runtime config.

### Action Items

1. **Migrate config keys** - Update `config/*.exs` files
2. **Search for references** - Run `grep -R "Core\." config/`
3. **Test all environments** - Verify dev/test/prod configs work

```elixir
# Before
config :wanderer_kills, Core.Clock, enable_mocking: true

# After
config :wanderer_kills, WandererKills.Clock, enable_mocking: true
```

## 12. Document Public APIs and Add Module Docs (Low Priority)

### Why It Matters

Renamed/relocated modules need clear documentation so maintainers understand context responsibilities.

### Action Items

1. **Update @moduledoc** - Every context module needs clear purpose documentation
2. **Review @doc and @spec** - Ensure public functions are properly documented
3. **Add usage examples** - Show how contexts interact

```elixir
defmodule WandererKills.Killmails do
  @moduledoc """
  Context for managing EVE Online killmail data.

  Handles parsing, enriching, storing, and retrieving killmail information
  from various sources including zKillboard and ESI API.
  """
end
```

## 13. Ensure Logging/Telemetry Consistency (Low Priority)

### Why It Matters

Module moves can break telemetry events and make logs reference incorrect module names.

### Action Items

1. **Update telemetry events** - Ensure event metadata uses new module names
2. **Verify log output** - Run end-to-end scenarios and check log sources
3. **Update monitoring** - Adjust any dashboards expecting old module names

```elixir
# Ensure logs show new paths
Logger.info("Ship types updated", module: WandererKills.ShipTypes.Updater)
```

## 14. Enhance Type Safety (Low Priority)

### Issues

- Inconsistent return patterns
- Specs don't match actual return values
- Duplicate result handling code

### Solution

Standardize return types and create shared result utilities.

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

1. ✅ **Consolidate CSV parsing** - Create unified CSV module (~300 lines reduction)
2. ✅ **Clean up configuration** - Simplify config access and migrate config/\*.exs keys
3. ✅ **Remove dead code** - Clean up unused code and audit/remove unused dependencies
4. ✅ **Standardize return types** - Create shared result utilities

### Phase 2: Architecture (Week 3-4)

1. **Reorganize by domain** - Move modules to new context structure
2. **Simplify cache architecture** - Flatten hierarchy and remove single-child supervisors
3. **Consolidate core utilities** - Move away from "core" namespace
4. **Update web layer** - Align wanderer_kills_web with new context paths

### Phase 3: Polish (Week 5-6)

1. **Reorganize tests** - Mirror new domain structure in test directory
2. **Improve naming consistency** - Standardize module naming patterns
3. **Enhance documentation** - Update @moduledoc/@doc for all contexts
4. **Enable CI checks** - Add Credo/Dialyzer/format checking to pipeline
5. **Verify logging/telemetry** - Ensure consistent module names in observability

## Success Metrics

- **Reduce LOC**: 15-20% reduction through deduplication
- **Improve maintainability**: Clearer module responsibilities
- **Better developer experience**: Easier code navigation
- **Align with conventions**: Follow Elixir best practices
- **Consistent quality**: All CI checks passing with new structure
