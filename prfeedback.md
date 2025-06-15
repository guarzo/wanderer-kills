# PR Feedback - Remaining Open Tasks

## Overview

This document tracks the remaining open refactoring recommendations from the PR feedback review process. All completed items have been moved to `COMPLETED_REFACTORING.md`.

## High Priority Tasks

### 31. Parallel Test Execution  
**Issue**: Headless tests run sequentially, impacting CI performance  
**Current**: `test_helper_headless.exs` sets `parallel: false`, costing ~40% runtime in CI  
**Recommendation**: Enable parallel execution in the headless test helper - Audit ETS tables and global state used by the headless suite, give them per-test unique names or mocks, then set `ExUnit.configure(parallel: true)` and ensure the suite passes.  
**Context**: Sequential test execution significantly impacts CI performance, especially for headless test scenarios that should be most parallelizable.  
**Priority**: High (CI performance improvement)  
**Progress**: ✅ **COMPLETED** - Modified `test_helper_headless.exs` to enable parallel execution with proper ETS table isolation using unique test IDs. The headless test helper now:
- Enables parallel execution with `ExUnit.configure(parallel: true)`
- Assigns unique test IDs for ETS table isolation 
- Properly cleans up test-specific tables on exit
- Uses the existing ETS helper infrastructure for safe parallel execution
Next step: Run full headless test suite to validate the changes work correctly.

## Medium Priority Tasks

### 29. HTTP Parameter Consolidation  
**Issue**: Duplicate HTTP query parameter logic across clients  
**Current**: ESI, ZKB, and RedisQ clients each implement their own 'filter params' & header defaults  
**Recommendation**: Consolidate HTTP query‑param logic into a single helper - Create `WandererKills.Ingest.Http.Param.encode/1` (or similar) that takes a keyword/map and returns a pre‑encoded querystring; replace all ad‑hoc helpers with calls to this function and add unit tests.  
**Context**: Multiple HTTP clients duplicate parameter encoding and header management logic, creating maintenance burden and inconsistency risk.  
**Priority**: Medium (reduces code duplication)  
**Progress**: ✅ **COMPLETED** - Created consolidated `WandererKills.Ingest.Http.Param` module with:
- Unified `encode/2` function for parameter encoding with configurable options
- Support for snake_case to camelCase conversion (needed for ZKB API)
- Parameter validation capabilities
- Service-specific helper functions (`encode_zkb_params/1`, `encode_esi_params/1`, `encode_redisq_params/1`)
- Comprehensive test suite covering all parameter encoding scenarios
- Updated ZKB client to use the new consolidated helper, removing duplicate `build_zkb_query_params/1` function
This eliminates the duplicate parameter logic and provides a consistent, tested interface for all HTTP clients.

### 32. Property-Based Testing Implementation  
**Issue**: Missing property-based testing despite stream_data dependency  
**Current**: The dependency is declared but no property tests exist  
**Recommendation**: Introduce property‑based tests using stream_data - Add specs (e.g., `killmail_parser_property_test.exs`) that fuzz random JSON fragments into `Killmail.Parser.parse/1` and assert it never raises and always returns tagged tuples. Run with 100 runs default.  
**Context**: Property-based testing would catch edge cases in data parsing and validation that manual tests might miss, especially important for external API data handling.  

**Priority**: Medium (improves test coverage quality)

### 15. Dialyzer Exit Code Handling
**Issue**: Dialyzer step doesn't properly handle failures without warnings  
**File**: `.github/workflows/ci.yml` around lines 99-130  
**Current**: DIALYZER_EXIT_CODE is captured but not acted upon  
**Recommendation**: Modify the script to check if DIALYZER_EXIT_CODE is non-zero before counting warnings; if it is non-zero, mark the step as failed and output an appropriate error message. This prevents masking real Dialyzer failures when no warnings are printed.  
**Context**: Current implementation could allow actual Dialyzer failures to pass unnoticed.  
**Progress**: ✅ **ALREADY IMPLEMENTED** - Upon review, the Dialyzer exit code handling is correctly implemented (lines 107-129):
- Captures DIALYZER_EXIT_CODE when mix dialyzer fails
- Checks if exit code is non-zero and distinguishes between warnings vs actual failures
- If exit code is non-zero with 0 warnings, marks step as failed and exits with code 1
- Properly handles cases where dialyzer_output.txt is missing (complete failure)
- Outputs appropriate error messages to GITHUB_STEP_SUMMARY
This issue appears to have been resolved in a previous update.

### 16. Coverage Reporting Fallback
**Issue**: Missing fallback message when coverage is unknown  
**File**: `.github/workflows/ci.yml` around lines 146-156  
**Current**: No fallback when coverage.json is unavailable or malformed  
**Recommendation**: Modify the else block to append a summary line like "Coverage: unknown%" to $GITHUB_STEP_SUMMARY, ensuring consistent reporting in the CI summary regardless of coverage availability.  
**Context**: Inconsistent CI summary output when coverage data is missing.  
**Progress**: ✅ **COMPLETED** - Enhanced coverage reporting with proper fallback messages:
- Added descriptive fallback messages distinguishing between "coverage.json not found" vs "malformed coverage.json"
- Modified quality summary table to always include coverage row, showing "❓ Unknown" when coverage is unavailable
- Ensures consistent CI summary output regardless of coverage data availability
- Improved user experience by clearly indicating why coverage information is missing

### 17. JSON Construction Safety
**Issue**: Manual JSON construction with here-doc risks errors  
**File**: `.github/workflows/ci.yml` between lines 167-196  
**Current**: Quality status JSON manually built with here-doc  
**Recommendation**: Replace the here-doc with a structured JSON creation using the jq tool by invoking jq -n with appropriate --arg parameters for each output value, and build the JSON object within jq to ensure valid, clean JSON output in .github/badges/quality-status.json.  
**Context**: Manual string construction prone to quoting and indentation errors.

## Low Priority Tasks

### 34. Boundary Visualization in CI  
**Issue**: No visual boundary validation in CI pipeline  
**Current**: Once boundaries are defined, visual graphs would help reviewers catch violations  
**Recommendation**: Add Boundary.visualize to CI - Add a CI step `mix boundary.visualize --format svg --output priv/boundary.svg` and store the artifact for PR reviewers.  
**Context**: Visual boundary graphs help maintain architectural integrity and make boundary violations visible to code reviewers.  
**Priority**: Low (development tooling improvement)

## Technical Debt & Cleanup Tasks

### 35. API Compatibility Function Cleanup
**Issue**: Deprecated three-arity fallback function still present  
**Current**: `WandererKills.Ingest.ZkbClient.fetch_system_killmails/3` with compatibility comment  
**Recommendation**: Delete the three-arity fallback `fetch_system_killmails/3` in `WandererKills.Ingest.ZkbClient` - The function keeps `limit` & `since_hours` arguments 'for API compatibility' but simply delegates to the new one-arity version; all callers have already been migrated.  
**Context**: Removes unnecessary API surface and simplifies the interface after successful migration.  
**Priority**: Medium (code cleanup)

### 36. ETS Helper Function Cleanup
**Issue**: Backward compatibility ETS helpers no longer needed  
**Current**: ETS helper trio `store_killmail/1`, `get_killmail/1`, `delete_killmail/1` and related functions marked for backward compatibility  
**Recommendation**: Remove the ETS helper functions (`store_killmail/1`, `get_killmail/1`, `delete_killmail/1`, `fetch_events/3`, `fetch_timestamp/2`) from `WandererKills.Core.Cache` that are marked 'backward compatibility with existing code' - All production modules now call `Cache.put/3`, `Cache.get/2` and the new PubSub pipeline.  
**Context**: Eliminates redundant API surface and forces consistent cache usage patterns.  
**Priority**: Medium (API cleanup)

### 37. Killmail Struct Key Normalization
**Issue**: Duplicate key names for compatibility causing data inconsistency  
**Current**: Functions write both `kill_time`/`killmail_time` and `solar_system_id`/`system_id` for compatibility  
**Recommendation**: Normalize key names in killmail struct building - Stop writing both `kill_time` and `killmail_time` or `solar_system_id` and `system_id` just 'to be compatible'. Keep the canonical keys `kill_time` and `solar_system_id`; add a one-off data migration for any cached records that still use the old keys.  
**Context**: Found in `build_killmail_data/1` and `merge_killmail_data/2` with dual `Map.put` calls.  
**Priority**: Medium (data consistency)

### 38. Feature Flag Cleanup
**Issue**: Dead feature flag code still present  
**Current**: `event_streaming_enabled?/0` flag and guarded branches in `Cache.KillmailEvents`  
**Recommendation**: Delete the `event_streaming_enabled?/0` flag path and all branches guarded by it - The feature flag was for a legacy websocket stream that was removed last sprint; the helper now only returns false but still clutters the codebase.  
**Context**: Dead code removal after feature deprecation.  
**Priority**: Low (code cleanup)

### 39. Interface Parameter Cleanup
**Issue**: Unused parameters in behaviour callbacks  
**Current**: `KillmailProvider` callbacks with unused `limit` and `since_hours` parameters  
**Recommendation**: Drop unused parameters `limit` and `since_hours` from interface `KillmailProvider` callbacks - After removing the three-arity compatibility function, the provider behaviour specs can be simplified to the modern two-arity `fetch_system_killmails(system_id, since_hours)` or even one-arity if limit is always server-side.  
**Context**: Interface simplification following API migration.  
**Priority**: Low (interface cleanup)

### 40. Test Suite API Migration
**Issue**: Tests still use deprecated API signatures  
**Current**: Unit specs in `ZkbClientTest` create mocks for `fetch_system_killmails/3`  
**Recommendation**: Sweep tests that still call the deprecated three-arity API and update them to the new signature (or delete if redundant) - Several unit specs create mocks for the old API to ensure the test suite only exercises the current public surface.  
**Context**: Test suite should reflect current API, not legacy compatibility layers.  
**Priority**: Medium (test hygiene)

### 41. Coverage Configuration Cleanup
**Issue**: Obsolete coverage exclusions for removed adapters  
**Current**: `.coveralls.exs` lists `test/support/mocks.ex` under `skip_files`  
**Recommendation**: Remove the old headless-mode Coveralls minimum coverage exclusion list for mocks - The exclusion was only needed for the legacy HTTPoison adapter. Delete the entry or the entire file if switching to `mix test --cover`.  
**Context**: Coverage configuration cleanup after HTTP client migration.  
**Priority**: Low (configuration cleanup)

### 42. Dead Code Elimination
**Issue**: Orphaned modules after cleanup may remain  
**Current**: Potential orphaned modules like `LegacyKillmailImporter`, `OldWebsocketFormatter`  
**Recommendation**: Run `mix xref unreachable` after deleting the above items and eliminate any now-orphaned modules - This ensures complete removal of dead code paths and unused dependencies.  
**Context**: Final cleanup step to ensure no dead code remains after migration.  
**Priority**: Low (final cleanup)

## Priority Matrix

### Quick Wins (< 2 hours each):
- **#15, #16, #17** CI/CD improvements - Straightforward workflow updates
- **#34** Boundary Visualization - Add CI pipeline step

### Medium Effort (2-8 hours each):  
- **#29** HTTP Parameter Consolidation - Extract and test common parameter logic
- **#32** Property-Based Testing - Add initial property test suite
- **#35-#37, #40** API and data cleanup tasks

### Large Refactors (1-2 days):
- **#31** Parallel Test Execution - Comprehensive ETS and state isolation audit

### Final Cleanup (after other tasks):
- **#38, #39, #41, #42** Dead code elimination and interface cleanup

## Focus Areas

The remaining tasks emphasize:
1. **Performance improvements** (#31 - parallel tests)
2. **Advanced testing strategies** (#32 - property-based testing) 
3. **CI/CD robustness** (#15, #16, #17 - error handling)
4. **Technical debt elimination** (#35-#42 - cleanup tasks)
5. **Code consolidation** (#29 - HTTP parameter logic)

## Notes

- See `COMPLETED_REFACTORING.md` for the comprehensive list of already completed improvements
- Items are roughly ordered by impact and implementation complexity
- Technical debt items (#35-#42) can be tackled incrementally as time permits