# PR Feedback - Remaining Refactoring Recommendations

## Code Duplication & Consolidation

### 1. HTTP Parameter Encoding
**Issue**: Potential for duplicate parameter filtering implementations  
**Current**: Single implementation found in `lib/wanderer_kills/ingest/http/client_provider.ex:106-116`  
**Recommendation**: Extract one `WandererKills.Ingest.Http.Param.encode/1` helper and ensure no duplicate 'filter_params' implementations emerge.  
**Context**: Currently well-consolidated, but should be extracted to prevent future duplication.

### 2. Cache Logic Consolidation
**Issue**: Multiple cache access patterns (direct Cachex calls, Cache.Helper, ETS adapters)  
**Recommendation**: Consolidate cache logic: keep a single public `WandererKills.Core.Cache` API that wraps Cachex; update tests to call this API instead of bespoke ETS helpers.  
**Context**: Found mixed usage of `Cachex` directly, `WandererKills.Core.Cache.Helper`, and ETS-based adapters throughout codebase.

### 3. Logging Strategy
**Issue**: Mixed logging approaches throughout codebase  
**Current**: Both `WandererKills.Core.Support.Logger` and direct `Logger` usage  
**Recommendation**: Pick one logging strategy: either delete `Support.Logger` and require Logger everywhere, or hide Logger completely behind `Support.Logger`; remove the mixed approach.  
**Context**: Some modules use structured logging via `Support.Logger`, others use standard `Logger` directly.

### 4. HTTP Client Provider
**Issue**: Unnecessary abstraction layer  
**Current**: `WandererKills.Ingest.Http.ClientProvider` module  
**Recommendation**: Delete `WandererKills.Ingest.Http.ClientProvider` and merge its defaults directly into `WandererKills.Ingest.Http.Client`.  
**Context**: ClientProvider adds indirection without significant benefit.

## Naming & Structure Conventions

### 5. Module Naming Conventions
**Issue**: Inconsistent naming patterns for data vs process modules  
**Current**: `Core.Systems.KillmailManager`, `Core.Cache.Helper`, `Core.EtsManager`  
**Recommendation**: Rename helper/manager modules: use nouns for data (ShipTypes, Killmail) and add verb suffixes only for processes (ShipTypes.Updater, Subscription.Manager).  
**Context**: Found various "helper" and "manager" suffixes used inconsistently.

### 6. Domain Structs
**Issue**: Extensive use of plain maps instead of typed structs  
**Current**: Only 4 modules define structs (Error, UnifiedStatus, RedisQ.State, SubscriptionManager)  
**Recommendation**: Introduce domain structs (e.g., %Killmail{}) and replace loose maps; add type-checked constructor helpers.  
**Context**: Most killmail and game data passed as untyped maps throughout the system.

## Code Quality & Style

### 7. Control Flow Complexity
**Issue**: Deep nested case/if statements  
**Current**: 76 files with potential nested control structures  
**Recommendation**: Replace deep nested case/if trees with small pure helpers and with chains; favour `Enum.flat_map_reduce/3` where you need both data and stats.  
**Context**: Common in error handling and data transformation code.

## OTP & Supervision

### 8. Task Supervision
**Issue**: Manual supervision tree configuration  
**Current**: Complex child specifications in application.ex  
**Recommendation**: Use `Task.Supervisor.child_spec/1` (or default values) instead of manually crafting `{Task.Supervisor, …}` tuples throughout the supervision tree.  
**Context**: Current supervision tree has conditional logic and manual specifications.

### 9. WebSocket Architecture
**Issue**: Single GenServer for all WebSocket connections  
**Recommendation**: Convert the single WebSocket GenServer into a DynamicSupervisor + Registry pattern where each live subscription is its own child for crash isolation.  
**Context**: Current design doesn't isolate individual connection failures.

## Configuration & Dependencies

### 10. Configuration Management
**Issue**: Custom configuration module instead of standard approach  
**Current**: `WandererKills.Core.Config` module with nested/flat access  
**Recommendation**: Swap the hand-rolled `WandererKills.Core.Config` for straight `Application.compile_env/3`; keep a helper only for computed defaults.  
**Context**: Config module adds abstraction over standard Elixir configuration.

### 11. Web Separation
**Issue**: Phoenix dependencies required for non-web functionality  
**Recommendation**: Extract `wanderer_kills_web` into a separate mix app so CLI/tests can run headless without pulling Phoenix.  
**Context**: All functionality currently requires full Phoenix stack.

## Testing & Development

### 12. Benchmark Organization
**Issue**: Benchmarks in test directory  
**Current**: Files in `/app/test/benchmarks/`  
**Recommendation**: Move benchmark scripts from `test/benchmarks/` to `bench/` (or `dev/bench/`) so CI doesn't execute them with `mix test`.  
**Context**: Found `batch_processor_benchmark.exs` and `migration_performance_test.exs` in test directory.

### 13. Test Helper Organization
**Issue**: Repetitive test setup code  
**Current**: Helpers in `/app/test/support/` but loaded individually  
**Recommendation**: Centralise Mox & helper modules under `test/support/**` and autoload them from `test_helper.exs` to remove the large per-file preambles.  
**Context**: Multiple test helper modules exist but require manual inclusion.

### 14. Type Specifications
**Issue**: Missing type safety  
**Current**: Only 62 files have @spec annotations  
**Recommendation**: Add missing @spec annotations to every public function and ensure Dialyzer passes cleanly.  
**Context**: Controllers, channels, and many business logic modules lack specifications.

## CI/CD & Documentation

### 15. Dialyzer Exit Code Handling
**Issue**: Dialyzer step doesn't properly handle failures without warnings  
**File**: `.github/workflows/ci.yml` around lines 99-130  
**Current**: DIALYZER_EXIT_CODE is captured but not acted upon  
**Recommendation**: Modify the script to check if DIALYZER_EXIT_CODE is non-zero before counting warnings; if it is non-zero, mark the step as failed and output an appropriate error message. This prevents masking real Dialyzer failures when no warnings are printed.  
**Context**: Current implementation could allow actual Dialyzer failures to pass unnoticed.

### 16. Coverage Reporting Fallback
**Issue**: Missing fallback message when coverage is unknown  
**File**: `.github/workflows/ci.yml` around lines 146-156  
**Current**: No fallback when coverage.json is unavailable or malformed  
**Recommendation**: Modify the else block to append a summary line like "Coverage: unknown%" to $GITHUB_STEP_SUMMARY, ensuring consistent reporting in the CI summary regardless of coverage availability.  
**Context**: Inconsistent CI summary output when coverage data is missing.

### 17. JSON Construction Safety
**Issue**: Manual JSON construction with here-doc risks errors  
**File**: `.github/workflows/ci.yml` between lines 167-196  
**Current**: Quality status JSON manually built with here-doc  
**Recommendation**: Replace the here-doc with a structured JSON creation using the jq tool by invoking jq -n with appropriate --arg parameters for each output value, and build the JSON object within jq to ensure valid, clean JSON output in .github/badges/quality-status.json.  
**Context**: Manual string construction prone to quoting and indentation errors.

## Advanced Testing Improvements

### 18. Placeholder Test Cleanup
**Issue**: Tests that only contain assert true placeholders  
**Current**: Some tests remain from removed functionality that don't test actual behavior  
**Recommendation**: Delete or mark pending all tests that only contain assert true placeholders.  
**Context**: Found in `test/shared/http_util_test.exs` and potentially other files.

### 19. Parallel Test Execution
**Issue**: Tests run sequentially reducing CI speed  
**Current**: `ExUnit.configure(parallel: false)` in test_helper.exs  
**Recommendation**: Re-enable ExUnit parallel execution; give ETS tables per-test unique names and run Mox in local mode with verify_on_exit!().  
**Context**: Current sequential execution limits test performance and CI speed.

### 20. Global Mock Strategy
**Issue**: Global Mox stubs make tests less isolated  
**Current**: Global stubs in test_helper.exs  
**Recommendation**: Replace global Mox stubs with explicit expect/4 calls inside each test and call verify_on_exit! in setup.  
**Context**: Current approach reduces test isolation and makes debugging harder.

### 21. Unified Test Case
**Issue**: Inconsistent test setup across test files  
**Current**: Various test case patterns and manual setup  
**Recommendation**: Create a unified DataCase that starts the application under supervision, clears caches on exit, and injects helpers.  
**Context**: Would provide consistent test environment and reduce boilerplate.

### 22. Performance Test Organization
**Issue**: Long-running performance tests slow down regular test runs  
**Current**: Performance tests mixed with unit tests  
**Recommendation**: Move long-running performance specs to test/performance/ and tag them with @tag :perf so they are skipped by default.  
**Context**: Would improve regular test suite speed while preserving performance testing.

### 23. Property-Based Testing
**Issue**: Limited test coverage for edge cases  
**Current**: Manual test cases only  
**Recommendation**: Add stream_data and create property-based tests for killmail parsing and cache helpers.  
**Context**: Would improve confidence in edge case handling and data validation.

### 24. Test Data Factory
**Issue**: Manual map fixtures throughout tests  
**Current**: Tests create data structures manually  
**Recommendation**: Introduce a Factory module (or ex_machina) and remove manual map fixtures.  
**Context**: Would improve test maintainability and reduce duplication.

### 25. Coverage Goals
**Issue**: Low test coverage standards  
**Current**: Coverage tracking without enforcement  
**Recommendation**: After cleaning up stubs, re-run coverage and raise the minimum to 85%.  
**Context**: Would ensure better code quality and confidence in changes.

### 26. Benchmark File Location
**Issue**: Benchmarks in test path executed by ExUnit  
**Current**: Benchmark files in `/app/test/benchmarks/`  
**Recommendation**: Relocate benchmark files from test/benchmarks to /bench outside the ExUnit path.  
**Context**: Prevents benchmarks from running during regular test execution.

### 27. Log Assertion Testing
**Issue**: Missing verification of log output in error scenarios  
**Current**: Error paths not verified for proper logging  
**Recommendation**: Use capture_log/3 to assert that expected warnings and errors are logged in failure scenarios.  
**Context**: Would verify that error conditions are properly logged for debugging.

## Priority Recommendations

1. **Quick Wins** (< 2 hours each):
   - CI/CD improvements (#15, #16, #17)
   - Move benchmarks (#12, #26) 
   - Delete placeholder tests (#18)

2. **Medium Effort** (2-8 hours each):
   - HTTP Client Provider consolidation (#4)
   - Cache logic consolidation (#2)
   - Logging strategy (#3)
   - Test helper organization (#13)
   - Type specifications (#14)

3. **Large Refactors** (days/weeks):
   - Domain structs (#6)
   - WebSocket architecture (#9)
   - Configuration management (#10)
   - Test infrastructure overhaul (#19, #20, #21)
   - Property-based testing (#23)

## Completed Items ✅

The following items from the original list have been **successfully completed**:

### Initial Refactoring
- ✅ **Phoenix Application Structure** - Fixed module namespace and location
- ✅ **Context-Based Module Organization** - Implemented `core/ingest/subs` structure  
- ✅ **Enforce Context Boundaries** - Added boundary library
- ✅ **Production Logging** - Removed emoji from logs
- ✅ **YAML/README Formatting** - Fixed all linting issues

### Recent Progress
- ✅ **CI/CD Improvements (#15, #16, #17)** - Fixed Dialyzer exit code handling, coverage reporting fallback, and JSON construction safety
- ✅ **Move benchmarks (#12, #26)** - Relocated benchmark files from test/benchmarks to bench/ directory
- ✅ **Delete placeholder tests (#18)** - Removed tests with only assert true placeholders
- ✅ **HTTP Client Provider consolidation (#4)** - Merged ClientProvider into Http.Client module
- ✅ **Cache logic consolidation (#2)** - Consolidated cache access through WandererKills.Core.Cache API
- ✅ **Logging strategy (#3)** - Standardized on direct Logger usage, removed Support.Logger
- ✅ **Module naming conventions (#5)** - Renamed Helper→Cache, Manager→Processor/Owner
- ✅ **Test helper organization (#13)** - Created TestCase and DataCase modules with centralized loading
- ✅ **Type specifications (#14)** - Added @spec annotations to all public functions in controllers and major modules
- ✅ **Task supervision (#8)** - Replaced unsupervised Task.async with Task.Supervisor throughout
- ✅ **Control flow complexity (#7)** - Simplified nested case/if statements with pipeline patterns
- ✅ **Configuration management (#10)** - Replaced custom Config module with standard Application.compile_env/3