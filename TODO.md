# TODO: Remaining PR Feedback Items

This document contains the remaining feedback items from prfeedback.md that require more extensive code review and changes. These items are organized by priority and complexity.

## High Priority / Performance Impact

### 1. Dynamic Atom Creation Risk
**File:** `lib/wanderer_kills/core/observability/metrics.ex:324-332`
**Issue:** The `safe_atom/1` function uses `String.to_atom/1` to create new atoms dynamically, which risks exhausting the BEAM atom table if given untrusted input.
**Solution:** Implement an allow-list or an ETS cache to store and reuse atoms for known metric names, preventing unbounded atom creation from arbitrary or user-supplied strings.
**Complexity:** High - requires careful design to prevent atom table exhaustion

### 2. Performance Issue with Subscription List Polling
**File:** `lib/wanderer_kills/subs/websocket/info.ex:91-94`
**Issue:** The call to `SubscriptionManager.list_subscriptions/0` happens on every status poll, which may cause performance issues if the subscription list grows large.
**Solution:** Implement caching or rate-limiting for the subscription list retrieval to reduce per-request allocations and improve efficiency, ensuring the cached data is refreshed appropriately to maintain accuracy.
**Complexity:** Medium - requires cache invalidation strategy

### 3. Rate Limiting Improvements
**File:** `lib/wanderer_kills/ingest/historical_fetcher.ex:485-492`
**Issue:** Hard-coded 60s sleep on rate-limit is a blunt, fixed delay.
**Solution:** If zkillboard returns a Retry-After header or the limiter exposes the expected wait, leverage that for faster recovery and less idle time.
**Example:**
```elixir
{:error, %Error{type: :rate_limit, retry_after: ms}} ->
  Logger.warning("Rate limited, waiting #{ms} ms", system_id: system_id)
  Process.sleep(ms)
  :retry
```
**Complexity:** Medium - requires HTTP header parsing and fallback logic

## Medium Priority / Code Quality

### ❌ 4. Configuration Optimization [NOT APPLIED]
**File:** `lib/wanderer_kills/ingest/esi/client.ex:495-496`
**Issue:** The call to `Application.get_env/3` is performed every time the function runs, causing repeated look-ups.
**Solution:** Retrieve the configuration once and store it in a module attribute at the top of the module, then reference this attribute in the function instead of calling `Application.get_env/3` repeatedly.
**Complexity:** Low - straightforward refactor
**Changes Made:** Configuration optimization was not applied due to test compatibility issues with compile-time resolution. Runtime configuration access remains for testability.

### ✅ 5. HTTP Client Consistency [COMPLETED]
**File:** `lib/wanderer_kills/ingest/esi/client.ex:231-233`
**Issue:** The function `get_killmail_raw/2` calls `HttpClient.get_with_rate_limit/1` directly, bypassing the configured HTTP client.
**Solution:** Replace the direct call with a call through the `http_client()/0` function to ensure the configured client is used, maintaining consistency and allowing proper test mocking.
**Complexity:** Low - straightforward refactor
**Changes Made:** Changed `HttpClient.get_with_rate_limit(url)` to `http_client().get_with_rate_limit(url, [])` to use configurable client with correct signature.

### ✅ 6. Key Consistency in Character Cache [COMPLETED]
**File:** `lib/wanderer_kills/ingest/killmails/character_cache.ex:167-170`
**Issue:** The code checks for the "killmail_id" key as a string but ignores the atom :killmail_id key, causing many cacheable killmails to be missed.
**Solution:** Update the key check in `Enum.split_with/2` to handle both string and atom keys by checking for either "killmail_id" or :killmail_id in the maps. Also, apply the same fix to `process_cacheable_killmails/1` to ensure consistent key access and accurate cache hit-rate metrics.
**Complexity:** Low - simple key handling update
**Changes Made:** Updated both `batch_extract_cached/1` and `process_cacheable_killmails/1` to handle both string and atom keys for killmail_id.

## Error Handling & Observability

### 7. Better Error Tagging
**File:** `lib/wanderer_kills/ingest/killmails/pipeline/coordinator.ex:254-256`
**Issue:** The call to `Enricher.enrich_killmail/1` returns errors that are only logged by the caller without specific tagging.
**Solution:** Modify `enrich_killmail/1` to wrap error tuples with a tagged tuple like `{:error, {:enrichment_failed, reason}}` so that upstream functions can pattern-match on this specific error and handle it more precisely.
**Complexity:** Low - error tuple wrapping

### 8. Enhanced Error Logging
**File:** `lib/wanderer_kills/core/observability/statistics.ex:295-326`
**Issue:** The rescue block catches all exceptions and returns `{:error, error}` without logging, which reduces visibility into failures.
**Solution:** Add proper logging inside the rescue block to record the error details before returning the error tuple. This will help with debugging in production while keeping the function tidy.
**Complexity:** Low - add logging

### 9. Stack Trace Preservation
**File:** `lib/wanderer_kills/ingest/killmails/time_filters.ex:302-318`
**Issue:** The current rescue block catches exceptions but discards the stack trace, hindering debugging.
**Solution:** Wrap the `Enum.filter` call inside an explicit `try ... rescue` block that re-raises the error with the original stack trace or propagates it properly, ensuring the stack trace is preserved for downstream debugging.
**Complexity:** Medium - requires careful exception handling

### 10. Improved Stack Trace Logging
**File:** `lib/wanderer_kills/ingest/killmails/pipeline/enricher.ex:182-198`
**Issue:** The rescue block doesn't log the full stacktrace.
**Solution:** Update the rescue block to log the full stacktrace by replacing the current error logging with `Logger.warning` including `Exception.format(:error, error, __STACKTRACE__)` for better debugging.
**Complexity:** Low - logging improvement

### 11. ETS Access Error Logging
**File:** `lib/wanderer_kills/core/observability/unified_status.ex:451-458`
**Issue:** The rescue clause silently swallows errors when accessing ETS info, which can hide issues.
**Solution:** Modify the rescue block to log a debug or warning message with the error details before returning 0, so failures in ETS access are recorded for troubleshooting.
**Complexity:** Low - add logging

### 12. Safe Apply Error Logging
**File:** `lib/wanderer_kills/core/observability/unified_status.ex:435-437`
**Issue:** The `safe_apply/4` function currently rescues and catches all exceptions silently, which hinders debugging.
**Solution:** Modify the rescue block to log a warning message including the error details before returning the default value, so operators can trace issues without interrupting execution.
**Complexity:** Low - add logging

## Code Structure & Maintainability

### 13. CSV Parser Refactoring
**File:** `lib/wanderer_kills/core/ship_types/parser.ex:86-104`
**Issue:** The `parse_csv_content` function uses a case statement that could be more readable.
**Solution:** Refactor to use a `with/else` construct instead of a case statement for better readability. Replace the case on `parsed_data` using a with/else construct that binds the parsed CSV result and then calls a helper function to handle the parsed data, returning `{:ok, result}` or `{:error, reason}`. Use the else block to return errors directly. Keep the existing rescue block for error logging and returning parse failure errors.
**Complexity:** Medium - structural refactor

### 14. Code Duplication Removal
**File:** `lib/wanderer_kills/ingest/killmails/enrichment/batch_enricher.ex:50-67`
**Issue:** The rescue and catch blocks contain duplicated code for logging errors and returning error tuples.
**Solution:** Refactor by extracting the common logging and error tuple construction logic into a private helper function that takes the error details as arguments. Then call this helper from both rescue and catch blocks to eliminate duplication and improve maintainability.
**Complexity:** Low - extract common function

### 15. Alias Organization
**File:** `lib/wanderer_kills/subs/subscriptions/base_index.ex:31-32, 61-63`
**Issue:** The alias `WandererKills.Core.Observability.Telemetry` is declared twice.
**Solution:** Remove the duplicate alias declarations inside the function and keep only the top-level alias to avoid redundancy and potential confusion.
**Complexity:** Low - remove duplicates

### 16. Test Helper Alias Consolidation
**File:** `test/test_helper.exs:71-74, 118-119`
**Issue:** Alias declarations are duplicated in multiple setup helpers and placed inside functions.
**Solution:** Move alias declarations to the module level at the top of the file so they are declared once and available throughout, reducing redundancy and improving maintainability.
**Complexity:** Low - move aliases to module level

## Code Style & Minor Issues

### 17. Module Reference Cleanup
**File:** `lib/wanderer_kills/core/observability/telemetry.ex:77-80, 424-437`
**Issue:** The alias `__MODULE__` should be removed to prevent potential name collisions with the `:telemetry` library.
**Solution:** Instead of aliasing `__MODULE__`, use the full module name or `__MODULE__` directly in function captures like `&__MODULE__.handle_cache_event/4` to maintain clarity and avoid confusion for future contributors.
**Complexity:** Low - replace alias with direct references

### 18. Test Mock Flexibility
**File:** `test/support/shared_contexts.ex:194-201`
**Issue:** Return map references un-aliased module, which could be more flexible.
**Solution:** Consider returning the configured mocks directly rather than hard-coding names to improve test flexibility:
```elixir
%{http_mock: HttpClientMock, esi_mock: EsiClientMock}
```
**Complexity:** Low - return value change

### 19. Telemetry Alias Consistency
**File:** `lib/wanderer_kills/ingest/killmails/character_cache.ex:183-200`
**Issue:** The rescue block calls `:telemetry.execute/3` directly to emit a bypass event, but the module already aliases Telemetry.
**Solution:** Replace the direct call to `:telemetry.execute/3` with the aliased `Telemetry.execute/3` to maintain naming consistency and abstraction.
**Complexity:** Low - use existing alias

### 20. Test Pattern Matching
**File:** `test/support/shared_contexts.ex:138-140`
**Issue:** The call to `KillmailStore.clear/0` currently ignores its result silently, which can hide errors during test setup.
**Solution:** Modify the code to explicitly match the result of `KillmailStore.clear/0`, for example by using a pattern match or a case statement, to ensure any errors are surfaced and handled properly.
**Complexity:** Low - add pattern matching

### 21. Function Parameter Clarity
**File:** `lib/wanderer_kills_web/channels/killmail_channel.ex:715-744`
**Issue:** The call to `maybe_unsubscribe_from_all_systems/3` uses `MapSet.new()` as the `current_systems` argument, which is unclear and confusing.
**Solution:** Rename the parameters of `maybe_unsubscribe_from_all_systems/3` to more descriptive names like `prev_systems` and `added_systems`, or create a dedicated helper function for character unsubscription flows that clearly sets these parameters. This will improve readability and prevent misuse in the future.
**Complexity:** Low - parameter naming/helper function

## Error Handling Improvements

### 22. Broader Exception Catching
**File:** `lib/wanderer_kills/ingest/killmails/batch_processor.ex:324-330`
**Issue:** The current rescue clause only catches `ArgumentError`, but `CharacterCache.extract_characters_cached/1` can also raise `:exit` or other runtime errors like ETS table crashes.
**Solution:** Broaden the rescue clause to catch all exceptions or errors that might occur during extraction, or refactor `CharacterCache.extract_characters_cached/1` to return `{:ok, result}` or `{:error, reason}` tuples and handle those explicitly instead of rescuing exceptions.
**Complexity:** Medium - requires analysis of possible exceptions

### 23. Test Exception Handling Improvement
**File:** `test/wanderer_kills/subscriptions/base_index_test.exs:45-57`
**Issue:** The `safe_clear/0` function currently rescues all exceptions and catches all exits, which hides legitimate errors from `TestEntityIndex.clear/0`.
**Solution:** Modify the rescue clause to only catch expected exceptions (e.g., specific known errors) and re-raise any other exceptions. Similarly, ensure the catch clause only handles expected exit reasons and re-raises unexpected ones. This will prevent swallowing unexpected errors and improve test reliability.
**Complexity:** Medium - requires understanding of expected vs unexpected errors

## Architecture Issues

### 24. Compile Error Fix
**File:** `lib/wanderer_kills/core/systems/killmail_processor.ex:129-146`
**Issue:** The catch clause is used outside a try block, which causes a compile error.
**Solution:** Wrap the entire case expression inside a try block, then place the catch clause after the try block to properly handle exceptions during processing.
**Complexity:** Medium - requires understanding of control flow

### 25. Metrics Collection Timing
**File:** `lib/wanderer_kills/core/observability/monitoring.ex:163-166, 173-176, 183-186`
**Issue:** The functions call `Metrics.increment_*` immediately after an asynchronous `GenServer.cast`, which can cause metrics to increment even if the cast fails due to the GenServer crashing.
**Solution:** Move the `Metrics.increment_*` calls inside the GenServer `handle_cast` callbacks so they only execute when the cast is successfully processed, ensuring the metrics stay in sync with the internal parser_stats state.
**Complexity:** Medium - requires understanding of GenServer lifecycle

---

## Recent Additions

The following items were added from the updated prfeedback.md:

### Code Style & Minor Issues
- **Item 19:** Telemetry Alias Consistency (character_cache.ex)
- **Item 20:** Test Pattern Matching (shared_contexts.ex)  
- **Item 21:** Function Parameter Clarity (killmail_channel.ex)

### Error Handling & Observability
- **Item 11:** ETS Access Error Logging (unified_status.ex)
- **Item 12:** Safe Apply Error Logging (unified_status.ex)

## Notes

- Items are roughly ordered by priority and impact
- Many of these changes should be done incrementally with proper testing
- Some items may require coordination with other team members for architecture decisions
- Consider creating separate PRs for groups of related changes rather than one massive PR
- **Updated Count:** This document now contains 25 items total (up from 20)
