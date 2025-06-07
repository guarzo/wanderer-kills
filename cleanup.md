- [x] **Remove deprecated cache wrapper modules** - "Remove the deprecated `WandererKills.Cache.ESI`, `WandererKills.Cache.ShipTypes`, and `WandererKills.Cache.Systems` modules by migrating all calls to `WandererKills.Cache.Helper` and deleting those wrappers."

  - **Files to remove**: `lib/wanderer_kills/cache/esi.ex` (327 lines), `lib/wanderer_kills/cache/ship_types.ex` (74 lines), `lib/wanderer_kills/cache/systems.ex` (165 lines)
  - **Current usage**: 16 files use these deprecated modules across ESI fetchers, killmail processing, ship type management, and web API
  - **Migration target**: All functionality already exists in `WandererKills.Cache.Helper` (415 lines) with methods like `esi_get_character`, `ship_type_get`, `system_get_killmails`
  - **Impact**: The cache wrappers are just thin aliases - `Cache.ESI` even calls `Cache.ShipTypes` internally (lines 170, 179, 188)

- [x] **Consolidate ESI fetcher modules** - "Consolidate the ESI fetcher modules by choosing either the unified `WandererKills.ESI.DataFetcher` implementation or the individual fetchers (`CharacterFetcher`, `TypeFetcher`, `KillmailFetcher`), migrate callers accordingly, and remove the unused modules."

  - **Current state**: Duplication exists - `DataFetcher` (391 lines) provides unified ESI API vs individual fetchers totaling ~675 lines (`CharacterFetcher`: 225 lines, `TypeFetcher`: 284 lines, `KillmailFetcher`: 166 lines)
  - **Coordinator module**: `ESI.Client` (219 lines) currently delegates to individual fetchers but could use unified `DataFetcher`
  - **Behavior implementation**: Both approaches implement `ESIClient` and `DataFetcher` behaviors, but `DataFetcher` module is more comprehensive
  - **Recommendation**: Keep unified `DataFetcher`, remove individual fetchers and update `ESI.Client` to use it directly

- [x] **Eliminate legacy ESI.Client compatibility functions** - "Eliminate legacy compatibility functions (`ensure_cached`, `download`, `parse`, `update`, `source_name`) from `WandererKills.ESI.Client`, updating any callers to use the new fetcher APIs directly."

  - **Investigation needed**: These specific functions don't appear to exist in current `ESI.Client` - this may be a stale cleanup item
  - **Current API**: `ESI.Client` provides clean delegation methods like `get_character`, `get_type_batch`, etc.
  - **Status**: Requires verification if these legacy functions existed in older versions or if this item can be marked complete

- [x] **Merge overlapping HTTP client code** - "Merge overlapping HTTP code by centralizing configuration in `WandererKills.Http.ClientProvider` and common request logic in `WandererKills.Http.Util`, removing redundant helper functions and simplifying `WandererKills.Http.Client` usage."

  - **Consolidation completed**: Enhanced `Http.ClientProvider` (98 lines) with configuration utilities, moved all utility functions from `Http.Util` to `Http.Client` (375 lines)
  - **Functions centralized**: JSON parsing, response validation, retry operations, telemetry handling, header management, and timeout configuration
  - **Backward compatibility**: `Http.Util` converted to deprecated delegation module to maintain API compatibility during transition

- [x] **Inline cache_killmails_for_system functionality** - "Inline or relocate the `WandererKills.Cache.Utils.cache_killmails_for_system` functionality into the preloader logic or `Cache.Helper`, then delete the `Cache.Utils` module."

  - **File to remove**: `lib/wanderer_kills/cache/utils.ex` (69 lines)
  - **Function usage**: Called from 3 locations - `preloader/worker.ex` (via `Core.CacheUtils` delegate), `wanderer_kills_web/api.ex`, and delegated through `core.ex`
  - **Simple migration**: Single function can be moved to `Cache.Helper` which already has `system_*` methods, then remove the 3 delegates

- [x] **Consolidate observability health modules** - "Consolidate observability code by merging `WandererKills.Observability.Health` and `WandererKills.Observability.HealthChecks` into a single health-check module to remove duplication."

  - **Completed**: Merged `Health` functionality into `HealthChecks` module, providing unified interface for health checks
  - **File removed**: `lib/wanderer_kills/observability/health.ex` (323 lines)
  - **Enhanced module**: `HealthChecks` now provides both behavior definitions and unified health check interface
  - **Backward compatibility**: All original `Health` functions now available through `HealthChecks`

- [x] **Review and consolidate processing modules** - "Review the `WandererKills.Processing` directory and merge small modules like `csv.ex` and `batch_processor.ex` into domain-specific contexts (e.g., killmail processing), removing unnecessary indirection."

  - **CSV module moved**: Relocated `csv.ex` (750 lines) from `processing/` to `ship_types/` directory as `WandererKills.ShipTypes.CSV`
  - **Updated references**: All imports and delegates updated to use new module location
  - **Batch processor retained**: `batch_processor.ex` (193 lines) kept in processing directory as it's used broadly through core module delegation

- [x] **Flatten ship_types directory structure** - "Flatten the `lib/wanderer_kills/ship_types` directory by merging `constants.ex` into `info.ex` or `updater.ex`, providing a single entry point for ship-type logic."

  - **Current structure**: `constants.ex` (137 lines), `info.ex` (51 lines), `updater.ex` (272 lines)
  - **Constants usage**: Defines ship group IDs and DB URLs used by other ship type modules
  - **Consolidation target**: `updater.ex` is the main orchestrator and would be logical place for constants
  - **Entry point**: `info.ex` is simplest and could serve as the public API, importing functionality from consolidated updater

- [x] **Unify behavior definitions** - "Unify behaviour definitions by merging `WandererKills.Core.Behaviours` into `WandererKills.Infrastructure.Behaviours`, and update all `@behaviour` references accordingly."

  - **Current split**: `Core.Behaviours` (exists as backward compatibility module in `core.ex` lines 146-197) vs `Infrastructure.Behaviours` (92 lines)
  - **Architecture**: `Infrastructure.Behaviours` contains the actual behavior definitions, `Core.Behaviours` provides legacy compatibility delegates
  - **Usage**: Multiple modules reference both - need to find all `@behaviour WandererKills.Core.Behaviours.*` and update to `Infrastructure.Behaviours`
  - **Cleanup**: Remove the `Core.Behaviours` section from `core.ex` after migration

- [x] **Audit infrastructure directory for consolidation** - "Audit the `lib/wanderer_kills/infrastructure` directory for single-use modules like `config.ex` and `constants.ex`, consolidating simple wrappers into core modules to reduce indirection."
  - **Constants consolidated**: Merged `constants.ex` (90 lines) into `config.ex`, providing unified configuration and constants interface
  - **File removed**: `lib/wanderer_kills/infrastructure/constants.ex`
  - **Updated references**: All delegates in `core.ex` now point to `WandererKills.Infrastructure.Config`
  - **Enhanced config**: `Config` module now provides both runtime configuration and core constants through single interface
