# PR Feedback

This document contains code review feedback for the WandererKills project.

## Performance Optimizations

### 1. Killmail Transformations - Unnecessary List Traversal ✅ COMPLETED
**File:** `lib/wanderer_kills/killmails/transformations.ex` (lines 137-152)

~~The `normalize_attackers_with_count` function recalculates the length of the normalized attackers list, causing an unnecessary second traversal. To optimize, use the length of the original attackers list instead of the normalized list when returning the count, as the count should be the same and this avoids extra computation.~~

**FIXED:** Changed `length(normalized)` to `length(attackers)` to avoid unnecessary second list traversal.

## Code Consistency & Style

### 2. Logger Metadata Key Consistency ✅ COMPLETED
**File:** `lib/wanderer_kills/killmails/transformations.ex` (lines 270-279)

~~Logger metadata keys are atoms but the killmail ID is accessed using a string key `"killmail_id"`. To improve consistency and readability, normalize the killmail map to use atom keys or use `Map.get/2` with an atom key like `:killmail_id` when accessing the ID for logging. This ensures all Logger metadata keys and values use atoms uniformly.~~

**FIXED:** Updated all logger calls to use `Map.get(killmail, :killmail_id) || killmail["killmail_id"]` for consistent atom key access while maintaining fallback to string keys.

### 3. Module Documentation Update ✅ COMPLETED
**File:** `lib/wanderer_kills/killmails/transformations.ex` (lines 26-29)

~~Update the module documentation to replace all references to the old function name `normalize_victim_data/1` with the new public function name `normalize_victim/1`. Adjust any examples and descriptions accordingly to ensure consistency between the docs and the current public API.~~

**FIXED:** Updated documentation examples to use correct function names: `normalize_victim_data` → `normalize_victim` and `normalize_attackers_data` → `normalize_attackers`.

## Configuration Improvements

### 4. Config Module - Inconsistent Group Fetching ✅ COMPLETED
**File:** `lib/wanderer_kills/config.ex` (lines 137-145)

~~The `get/2` function manually fetches `group_config` without using `get_group/1`, which handles keyword-to-map conversion. Refactor `get/2` to call `get_group/1` for fetching `group_config` to ensure consistent keyword-to-map conversion and safer nested key access, replacing the direct `Application.get_env` call with `get_group/1`.~~

**FIXED:** Replaced direct `Application.get_env` call with `get_group(group)` to ensure consistent keyword-to-map conversion and safer nested key access throughout the config module.

### 5. Config Group Merging Issue ✅ COMPLETED
**File:** `lib/wanderer_kills/config.ex` (lines 327-343)

~~The `get_group/1` function currently returns the environment config as-is, which causes it to discard any default keys not specified in the env config. To fix this, modify the function to deep-merge the default config for the group with the environment config by first converting the env config to a map if needed, then merging it with the defaults using `Map.merge/2` so that unspecified default keys are preserved alongside any overrides from the env config.~~

**FIXED:** Modified `get_group/1` to first get defaults and environment config separately, convert env config to map if needed, then use `Map.merge/2` to properly merge defaults with environment overrides, preserving all default keys.

### 6. Config Key Handling ✅ COMPLETED
**File:** `lib/wanderer_kills/config.ex` (lines 354-392)

~~The function `flat_to_nested_key/1` returns `nil` for unknown keys, but callers expect a `{group, path}` tuple. Modify the function to handle unrecognized keys by logging a warning and returning `{:unknown, []}` instead of `nil`, ensuring consistent return types and aiding troubleshooting.~~

**FIXED:** Modified `simple_prefix_mapping/1` to handle unrecognized keys by logging a warning with `Logger.warning/1` and returning `{:unknown, []}` instead of `nil` to ensure consistent return types and aid troubleshooting.

## CI/CD Improvements

### 7. YAML Formatting ✅ COMPLETED
**File:** `.github/workflows/ci.yml` (lines 35, 55, 65, 68)

~~Remove any trailing spaces at the end of these lines to fix YAMLlint warnings and keep the file clean. Ensure no extra spaces remain after the last character on these lines.~~

**FIXED:** Removed all trailing whitespace from the YAML file using `sed -i 's/[[:space:]]*$//'` to ensure clean formatting and eliminate YAMLlint warnings.

## Bug Fixes & Error Handling

### 8. ETS Race Condition ✅ COMPLETED
**File:** `lib/wanderer_kills/cache/ets_adapter.ex` (lines 51-63)

~~The current code checks for ETS table existence using `:ets.info/1`, which can cause a race condition if another process creates the table between the check and creation, leading to an `:argument_error`. To fix this, replace the existence check with `:ets.whereis(cache_name)` and verify if the result is a reference using `is_reference/1`, which provides an atomic and safe way to check if the table exists before creating it, preventing race conditions and ensuring callers receive a successful operation result.~~

**FIXED:** Replaced `:ets.info/1` check with `:ets.whereis(cache_name)` and `is_reference/1` guard to safely detect existing tables and prevent race conditions during table creation.

### 9. WebSocket Stats Error Pattern ✅ COMPLETED
**File:** `lib/wanderer_kills/killmails/transformations.ex` (lines 390-401)

~~The function `fallback_to_esi/2` only matches the tuple `{:error, %Error{type: :not_found}}`, but it should also handle the case `{:error, :not_found}` where the error is an atom. Update the pattern matching in `fallback_to_esi/2` to include both `{:error, %Error{type: :not_found}}` and `{:error, :not_found}` so that cache misses with the atom `:not_found` correctly fall back to ESI.~~

**FIXED:** Added pattern matching for `{:error, :not_found}` atom case in addition to the existing `{:error, %Error{type: :not_found}}` pattern, ensuring cache misses with both error formats correctly fall back to ESI.

*Note: Corrected file path from websocket_stats.ex to transformations.ex*

### 10. Pipeline Coordinator Exception Handling ✅ COMPLETED
**File:** `lib/wanderer_kills/killmails/pipeline/coordinator.ex` (lines 421-436)

~~The rescue clauses catch all `ArgumentError` and `BadMapError` exceptions broadly, which can mask real bugs. Refine the rescue clauses to only catch specific, expected error cases related to user input validation by pattern matching on the error details or messages. For unexpected errors, allow them to propagate normally so they can surface and be fixed, rather than converting all to generic error tuples.~~

**FIXED:** Refined rescue clauses to only catch specific expected errors (invalid dates, empty/nil data) and re-raise unexpected errors using `reraise error, __STACKTRACE__` to maintain normal error handling for debugging.

### 11. RedisQ Stats Double Counting ✅ COMPLETED
**File:** `lib/wanderer_kills/redisq.ex` (lines 218-225)

~~The `update_stats/2` function incorrectly increments both `legacy_kills` and `kills_received` for `:legacy_kill`, causing double counting in `kills_received`, and it never increments `total_legacy_kills`. To fix this, remove the increment of `kills_received` for `:legacy_kill` and add an increment for `total_legacy_kills` to ensure cumulative metrics are updated correctly without inflating `kills_received`.~~

**FIXED:** Removed `kills_received` increment for `:legacy_kill` and added `total_legacy_kills` increment to prevent double counting and ensure proper cumulative metrics tracking.

### 12. RedisQ Code Duplication ✅ COMPLETED
**File:** `lib/wanderer_kills/redisq.ex` (lines 428-436)

~~The function `next_schedule/2` has duplicate logic for the clauses `{:ok, :legacy_kill}` and `:kill_received`. Refactor by merging these clauses into a single clause that matches `{:ok, result}` when result is either `:kill_received` or `:legacy_kill`. Use a guard clause with `when result in [:kill_received, :legacy_kill]` and update the `Logger.debug` message to interpolate the result variable. This will reduce code duplication and keep the behavior consistent.~~

**FIXED:** Merged duplicate clauses into single function with guard clause `when result in [:kill_received, :legacy_kill]` and updated logger message to interpolate the result variable, reducing code duplication while maintaining consistent behavior.

## Test Improvements

### 13. Flaky Test Timing ✅ COMPLETED
**File:** `test/wanderer_kills/subscriptions/broadcaster_test.exs` (lines 248-252)

~~The assertion expects exactly 30 messages within a 2-second timeout, which can cause flaky test failures under CI load. To fix this, either increase the timeout duration in `receive_messages_until` to allow more time for messages to arrive or change the assertion to check that the number of received messages is at least 30 (`>= 30`) instead of exactly 30, ensuring the test is more resilient to timing variability.~~

**FIXED:** Increased timeout from 2000ms to 5000ms and changed assertion from `== 30` to `>= 30` to make the test more resilient to timing variability under CI load.

### 14. Webhook Notifier Test Config Dependency ✅ COMPLETED
**File:** `test/wanderer_kills/subscriptions/webhook_notifier_test.exs` (lines 252-257)

~~The test asserts that the timeout option is both above 5000 and below or equal to 30000, which can fail if the configuration changes to allow higher timeouts. To fix this, remove the upper bound assertion and only assert that `opts[:timeout]` is greater than or equal to 5000, or alternatively, read the expected timeout value from the configuration and assert against that to make the test flexible to config changes.~~

**FIXED:** Removed the upper bound assertion `<= 30_000` and kept only the minimum timeout check `>= 5000`, making the test flexible to configuration changes that might allow higher timeouts.

### 15. Ineffective Test Assertion ✅ COMPLETED
**File:** `test/wanderer_kills/subscription_manager_test.exs` (lines 166-173)

~~The test asserts a condition that is always true and does not verify any specific behavior. Update the test to assert the concrete expected outcome, such as verifying that invalid IDs are filtered out and the function returns success only if at least one valid ID remains, or remove the test if no specific behavior is guaranteed.~~

**FIXED:** Replaced the ineffective assertion that was always true with a concrete test that verifies the function correctly rejects invalid system IDs with the expected error message `"All system IDs must be integers"`.
