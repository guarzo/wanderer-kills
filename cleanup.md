# WandererKills Codebase Cleanup

This document outlines technical debt reduction and code organization improvements for the WandererKills application. Each item includes current state analysis, impact assessment, and implementation details.

## 1. Remove Deprecated HTTP Utility Module

**Status:** Ready for removal
**Impact:** Low risk - already marked deprecated with migration guide
**Location:** `lib/wanderer_kills/http/util.ex`

**Current State:**

- Module exists as a thin wrapper around `WandererKills.Http.Client` and `WandererKills.Http.ClientProvider`
- Contains 6 deprecated functions with `@deprecated` attributes
- All functionality has been moved to the target modules
- Includes comprehensive migration guide in module documentation

**Implementation:**

1. Search codebase for any remaining calls to `WandererKills.Http.Util.*`
2. Update callers to use direct calls to `Http.Client` and `Http.ClientProvider`
3. Delete the file: `lib/wanderer_kills/http/util.ex`

**Files to Update:**

- Remove: `lib/wanderer_kills/http/util.ex` (44 lines)
- Search for usage patterns: `Http.Util.`, `WandererKills.Http.Util`

---

## 2. Eliminate Legacy Configuration Functions

**Status:** Ready for refactoring
**Impact:** Medium - affects multiple modules using legacy config API
**Location:** `lib/wanderer_kills/infrastructure/config.ex` (lines 320-340)

**Current State:**

- Legacy compatibility functions exist: `cache_ttl/1`, `batch_concurrency/1`, `request_timeout/1`
- Modern API available: `Config.cache()`, `Config.batch()`, `Config.timeouts()`
- Found 7 incoming dependencies to the Config module
- Configuration properly structured with nested maps

**Legacy Functions to Remove:**

```elixir
def cache_ttl(:killmails), do: cache().killmails_ttl
def cache_ttl(:system), do: cache().system_ttl
def cache_ttl(:esi), do: cache().esi_ttl
def cache_ttl(:esi_killmail), do: cache().esi_killmail_ttl
def batch_concurrency(:esi), do: batch().concurrency_esi
def batch_concurrency(:zkb), do: batch().concurrency_zkb
def batch_concurrency(_), do: batch().concurrency_default
def request_timeout(:esi), do: timeouts().esi_request_ms
def request_timeout(:zkb), do: timeouts().zkb_request_ms
def request_timeout(:http), do: timeouts().http_request_ms
def request_timeout(_), do: timeouts().default_request_ms
```

**Implementation:**

1. Search codebase for calls to legacy functions
2. Replace with modern API calls (e.g., `Config.cache().killmails_ttl`)
3. Delete legacy function definitions
4. Update tests to use new API

---

## 3. Consolidate Single-File Directories

**Status:** Ready for restructuring
**Impact:** Medium - improves code organization and discoverability
**Locations:**

- `lib/wanderer_kills/processing/batch_processor.ex` (193 lines)
- `lib/wanderer_kills/zkb/client.ex` (654 lines)

**Current State:**

- Processing directory contains only `batch_processor.ex`
- ZKB directory contains only `client.ex`
- Both are substantial files with clear responsibilities
- Current structure creates unnecessary directory nesting

**Proposed Structure:**

```
# Move to domain-appropriate locations
lib/wanderer_kills/infrastructure/batch_processor.ex
lib/wanderer_kills/killmails/zkb_client.ex

```

**Implementation:**

1. Analyze dependencies and usage patterns for both files
2. Choose appropriate target locations based on domain context
3. Update module names and namespaces
4. Update all imports and references
5. Delete empty directories

---

## 4. Refactor Cache Helper ESI Compatibility Layer

**Status:** Ready for cleanup
**Impact:** Low - ESI wrapper functions are simple delegates
**Location:** `lib/wanderer_kills/cache/helper.ex` (lines 208-217)

**Current State:**

- Generic namespaced cache API exists and works well
- ESI compatibility layer provides 9 wrapper functions:
  - `esi_get_character/1`, `esi_get_corporation/1`, `esi_get_alliance/1`
  - `esi_get_or_set_*` variants for character, corporation, alliance, type, group, killmail
- All are thin wrappers around the modern API

**Functions to Remove:**

```elixir
def esi_get_character(id), do: character_get(id)
def esi_get_corporation(id), do: corporation_get(id)
def esi_get_alliance(id), do: alliance_get(id)
def esi_get_or_set_character(id, fallback_fn), do: character_get_or_set(id, fallback_fn)
def esi_get_or_set_corporation(id, fallback_fn), do: corporation_get_or_set(id, fallback_fn)
def esi_get_or_set_alliance(id, fallback_fn), do: alliance_get_or_set(id, fallback_fn)
def esi_get_or_set_type(id, fallback_fn), do: ship_type_get_or_set(id, fallback_fn)
def esi_get_or_set_group(id, fallback_fn), do: get_or_set("groups", to_string(id), fallback_fn)
def esi_get_or_set_killmail(id, fallback_fn), do: killmail_get_or_set(id, fallback_fn)
```

**Implementation:**

1. Search for usage of `esi_*` functions in codebase
2. Replace with direct calls to domain-specific functions
3. Remove ESI wrapper function definitions
4. Update documentation to reflect the modern API

---

## 5. Audit Infrastructure.Clock Redundant Overloads

**Status:** Ready for simplification
**Impact:** Low - straightforward function consolidation
**Location:** `lib/wanderer_kills/infrastructure/clock.ex`

**Current State:**

- Module is well-organized with clear responsibilities
- Contains both `system_time/0` and `system_time/1` functions
- Multiple time parsing and formatting functions
- Some potential for consolidation without losing functionality

**Functions to Audit:**

- Keep: `now/0`, `now_milliseconds/0`, `system_time/1`
- Review: Multiple time parsing functions, redundant formatters
- Consider: Consolidating similar datetime operations

**Implementation:**

1. Analyze usage patterns of all Clock functions
2. Identify truly redundant overloads
3. Consolidate where possible without breaking functionality
4. Update callers if function signatures change
5. Maintain comprehensive time handling for killmail processing

---

## 6. HTTP Client Responsibility Consolidation

**Status:** Needs analysis
**Impact:** Medium - affects HTTP request handling across application
**Locations:**

- `lib/wanderer_kills/http/client.ex` (418 lines)
- `lib/wanderer_kills/http/client_provider.ex` (118 lines)

**Current State:**

- Both modules have 4+ incoming dependencies each
- Potential overlap in HTTP client functionality
- ClientProvider may be providing configuration/setup for Client
- Need to analyze actual responsibilities vs. overlap

**Analysis Required:**

1. Map exact responsibilities of each module
2. Identify genuine overlap vs. separation of concerns
3. Determine if merger is beneficial or if clear delineation is better
4. Consider impact on testability and modularity

**Implementation Options:**

- **Option A:** Merge if truly redundant
- **Option B:** Clearly document and separate responsibilities if both are needed

---

## 7. Move KillStore to Killmails Namespace

**Status:** Ready for reorganization
**Impact:** Low - single file move with namespace update
**Current:** `lib/wanderer_kills/kill_store.ex` (180 lines)
**Target:** `lib/wanderer_kills/killmails/store.ex`

**Current State:**

- KillStore is logically part of killmail persistence
- Killmails directory already contains related modules: `parser.ex`, `enricher.ex`, `coordinator.ex`
- Module has 3 incoming dependencies
- Good candidate for namespace consolidation

**Implementation:**

1. Move file to `lib/wanderer_kills/killmails/store.ex`
2. Update module name from `WandererKills.KillStore` to `WandererKills.Killmails.Store`
3. Update all imports and references (3 known dependencies)
4. Update any configuration or supervision tree references

---

## 8. Consolidate Configuration Access

**Status:** Requires audit
**Impact:** Medium - standardizes configuration access patterns
**Scope:** Application-wide

**Current State:**

- Found `Application.get_env` usage in 3 application files:
  - `lib/wanderer_kills/infrastructure/config.ex`
  - `lib/wanderer_kills/http/client.ex`
  - `lib/wanderer_kills/core.ex`
- Modern `WandererKills.Infrastructure.Config` module exists and is well-structured
- Need to audit for scattered direct config access

**Implementation:**

1. Audit all application files for `Application.get_env/3` calls
2. Replace direct calls with `WandererKills.Infrastructure.Config` calls
3. Review config files for unused keys
4. Ensure consistent configuration access patterns

---

## 9. Eliminate Dead Code

**Status:** Use modern analysis tools
**Impact:** Reduces codebase size and maintenance burden

**Current State:**

- `mix xref unreachable` is deprecated and has no effect
- Need to use alternative analysis methods
- Current stats show 33 tracked files with good dependency tracking
- 4 cycles detected in dependency graph

**Alternative Analysis Methods:**

1. Use `mix xref graph --format stats` for dependency analysis
2. Use `mix xref callers ModuleName` for specific module usage
3. Manual code review of modules with zero incoming dependencies
4. Consider tools like `credo` for unused code detection

**Implementation:**

1. Run comprehensive dependency analysis
2. Identify modules/functions with no callers
3. Verify through manual review before removal
4. Remove confirmed dead code iteratively

---

## 10. Split Infrastructure.Behaviours File

**Status:** Ready for reorganization
**Impact:** Low - improves code discoverability
**Current:** `lib/wanderer_kills/infrastructure/behaviours.ex` (92 lines)

**Current State:**

- Single file contains 3 behaviour definitions:
  - `HttpClient` (8 callbacks)
  - `DataFetcher` (3 callbacks)
  - `ESIClient` (12 callbacks)
- Each behaviour is well-defined and substantial
- Could benefit from separation for better discoverability

**Proposed Structure:**

```
lib/wanderer_kills/behaviours/
├── http_client.ex        # HttpClient behaviour
├── data_fetcher.ex       # DataFetcher behaviour
└── esi_client.ex         # ESIClient behaviour
```

**Implementation:**

1. Create `lib/wanderer_kills/behaviours/` directory
2. Split behaviours into individual files
3. Update module names to match new structure
4. Update all imports and `@behaviour` declarations
5. Delete original `behaviours.ex`

---

## 11. Group Preloader Logic

**Status:** Ready for consolidation
**Impact:** Low - reduces directory nesting
**Locations:**

- `lib/wanderer_kills/preloader/supervisor.ex` (50 lines)
- `lib/wanderer_kills/preloader/worker.ex` (328 lines)

**Current State:**

- Small directory with only 2 files
- Supervisor is minimal (50 lines)
- Worker contains substantial logic (328 lines)
- Good candidate for consolidation

**Proposed Structure:**

```elixir
# lib/wanderer_kills/preloader.ex
defmodule WandererKills.Preloader do
  # Common preloader functionality

  defmodule Supervisor do
    # Current supervisor.ex content
  end

  defmodule Worker do
    # Current worker.ex content
  end
end
```

**Implementation:**

1. Create new `lib/wanderer_kills/preloader.ex`
2. Move supervisor logic to nested `Supervisor` module
3. Move worker logic to nested `Worker` module
4. Update module references in supervision tree
5. Delete original directory and files

---

## Implementation Priority

**High Priority** (Quick wins):

1. Remove deprecated HTTP utility module
2. Move KillStore to killmails namespace
3. Group Preloader logic
4. Split Infrastructure.Behaviours

**Medium Priority** (Requires more analysis): 5. Eliminate legacy configuration functions 6. Consolidate single-file directories 7. Consolidate configuration access 8. HTTP client responsibility analysis

**Low Priority** (Ongoing maintenance): 9. Audit Clock redundant overloads 10. Refactor Cache Helper ESI layer 11. Eliminate dead code (continuous process)

---

**Total Impact:** Estimated reduction of ~200 lines through consolidation and cleanup, with significantly improved code organization and maintainability.
