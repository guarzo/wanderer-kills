# WandererKills Codebase Cleanup Tasks

This document outlines technical debt and cleanup tasks identified during the codebase review. Tasks are prioritized by impact and complexity.

## High Priority Tasks

### 🔄 **Unify killmail store implementations**

**Status**: ✅ Already resolved
**Details**: The duplicate `lib/wanderer_kills/killmails/store.ex` mentioned in the original task no longer exists. Only `lib/wanderer_kills/kill_store.ex` remains as the primary ETS-based killmail storage implementation.

### 🗑️ **Eliminate legacy CSV update pipeline**

**Status**: ✅ Completed - Legacy duplication removed
**Action Taken**: Consolidated ship type CSV functionality into a single location in `lib/wanderer_kills/core/csv.ex`. Removed duplicate implementations while preserving CSV + ESI fallback strategy in `ship_types/updater.ex`.

### 🧹 **Consolidate caching wrappers**

**Status**: ✅ Completed - All cache modules consolidated
**Action Taken**:

- ✅ `WandererKills.Cache.Helper` enhanced with comprehensive domain-specific functions
- ✅ `lib/wanderer_kills/cache/ship_types.ex` converted to thin wrapper (was 158 lines, now ~50 lines)
- ✅ `lib/wanderer_kills/cache/systems.ex` converted to thin wrapper (was 347 lines, now ~140 lines)
- ✅ `lib/wanderer_kills/cache/esi.ex` converted to thin wrapper (was 486 lines, now ~185 lines)
  **Result**: Eliminated significant code duplication while maintaining backward compatibility.

## Medium Priority Tasks

### 🔌 **Abstract common HTTP client logic**

**Status**: ✅ Completed - HTTP patterns consolidated
**Action Taken**:

- ✅ Created `WandererKills.Core.Http.Util` with shared HTTP utilities
- ✅ Consolidated request patterns with `request_with_telemetry/3`
- ✅ Unified JSON response parsing with `parse_json_response/1`
- ✅ Standardized headers with `eve_api_headers/1`
- ✅ Refactored `lib/wanderer_kills/zkb/client.ex` to use shared utilities (reduced from 697 to ~640 lines)
- ✅ Updated `lib/wanderer_kills/esi/client.ex` to use unified HTTP client
- ✅ Removed duplicate error handling, retry logic, and response parsing
  **Result**: Eliminated HTTP client duplication while maintaining functionality and improving consistency.

### 🏗️ **Adopt domain-driven directory structure**

**Status**: ✅ Completed - Core directory restructured
**Action Taken**:

- ✅ Redistributed `core/` modules into domain-specific directories:
  - **HTTP modules** → `lib/wanderer_kills/http/` (client.ex, client_provider.ex, util.ex)
  - **Processing modules** → `lib/wanderer_kills/processing/` (batch_processor.ex, csv.ex)
  - **Cache utilities** → `lib/wanderer_kills/cache/` (utils.ex)
  - **Infrastructure modules** → `lib/wanderer_kills/infrastructure/` (config.ex, retry.ex, clock.ex, constants.ex, behaviours.ex, error.ex)
- ✅ Created compatibility module `WandererKills.Core` with aliases for backward compatibility
- ✅ Updated module names and internal references
- ✅ Removed empty `core/` directory

**New Structure**:

```
lib/wanderer_kills/
├── http/           # HTTP client utilities
├── processing/     # Data processing (CSV, batch operations)
├── cache/          # Cache modules and utilities
├── infrastructure/ # Core infrastructure (config, retry, error handling)
├── esi/            # ESI-related modules
├── zkb/            # ZKB-related modules
├── killmails/      # Killmail processing
├── ship_types/     # Ship type management
└── observability/  # Telemetry components
```

**Result**: Eliminated the catch-all `core/` directory and organized modules by domain responsibility.

## Low Priority Tasks

### 🧪 **Consolidate test helpers**

**Status**: ⚠️ Multiple helper files exist
**Current State**:

- `test/support/helpers.ex` (11KB, 451 lines) - Main helper functions
- `test/support/cache_helpers.ex` (3.5KB, 142 lines) - Cache-specific helpers
- `test/shared/cache_key_test.exs` (4.2KB, 119 lines) - Shared cache tests
  **Action Required**: Merge overlapping functionality, remove duplicate test cases.

### ⏰ **Simplify clock utilities**

**Status**: ⚠️ Complex compatibility layer present
**Location**: `lib/wanderer_kills/core/clock.ex` (340 lines)
**Issues**:

- Complex `get_system_time_with_config/1` function with multiple override branches
- Configurable `:clock` overrides add complexity for testing
  **Action Required**: Remove compatibility branches, default to `DateTime.utc_now()` and `System.system_time/1`.

### ⚙️ **Prune unused config entries**

**Status**: ⚠️ Needs investigation
**Locations**: `config/config.exs`, `config/dev.exs`, `config/test.exs`
**Action Required**: Review configuration files for:

- Commented-out or unused keys
- Legacy ESI CSV configuration entries
- Opportunities to consolidate flat keys into nested scopes

### 💀 **Remove dead code via analysis**

**Status**: ❓ Manual review needed
**Note**: `mix xref unreachable` has been moved to compiler and shows no output
**Action Required**:

- Manual code review to identify unused constants in `Core.Constants`
- Review for orphaned utility modules
- Check for unused functions in large modules

## Task Completion Checklist

- [x] Remove legacy CSV pipeline from `core/csv.ex`
- [x] Consolidate cache wrapper modules (All modules completed)
- [x] Extract common HTTP client patterns
- [ ] Restructure core directory into domain contexts
- [ ] Merge test helper modules
- [ ] Simplify clock utility complexity
- [ ] Clean up configuration files
- [ ] Manual dead code review and removal

---

**Last Updated**: Based on codebase analysis as of current state  
**Total Files Reviewed**: ~50+ files across lib/, test/, and config/ directories
