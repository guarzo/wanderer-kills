# PR Feedback Review

## 1. Logger Level in Config Module ✅
**File**: `lib/wanderer_kills/config.ex` (lines 348-350)  
**Issue**: Change log level from `Logger.debug` to `Logger.warning` for unknown config types  
**Context**: In the config normalization function, when an unknown config type is encountered, it's currently logged at debug level. This should be elevated to warning level since misconfigurations could cause runtime issues.  
**Fix**: Replace `Logger.debug` with `Logger.warning`  
**Status**: COMPLETED - Changed Logger.debug to Logger.warning on line 349

## 2. Incomplete Kill Count in RedisQ Logs ✅
**File**: `lib/wanderer_kills/redisq.ex` (lines 276-284)  
**Issue**: Structured log field `redisq_kills_processed` omits `stats.legacy_kills`  
**Context**: The status reporting function logs various RedisQ statistics but only includes `stats.kills_received` in the processed count, missing legacy kills which are tracked separately.  
**Fix**: Update `redisq_kills_processed: stats.kills_received + stats.legacy_kills`  
**Status**: COMPLETED - Updated line 277 to include both kills_received and legacy_kills in the total

## 3. Compile-Time Cache Adapter Binding ✅
**File**: `lib/wanderer_kills/cache/helper.ex` (lines 30-31)  
**Issue**: Using `Application.compile_env/3` prevents runtime adapter changes  
**Context**: The cache adapter is bound at compile time using a module attribute, which prevents changing the adapter at runtime for testing or configuration changes.  
**Fix**: Create a private function `cache_adapter/0` that returns `@cache_adapter` and use it instead of direct module attribute access  
**Status**: COMPLETED - Added cache_adapter/0 function and replaced all 4 direct @cache_adapter usages with function calls

## 4. Async Tests with Shared PubSub State ✅
**File**: `test/wanderer_kills/subscriptions/broadcaster_test.exs` (lines 1-3)  
**Issue**: Test module marked as `async: true` causes flaky tests due to shared PubSub  
**Context**: The Broadcaster uses Phoenix PubSub for message broadcasting. Running tests concurrently can cause message interference between tests.  
**Fix**: Either set `async: false` or create isolated PubSub instances per test  
**Status**: COMPLETED - Changed async: true to async: false on line 2 to prevent concurrent test interference

## 5. Mixed Key Types in Logger Metadata ✅
**File**: `lib/wanderer_kills/killmails/transformations.ex` (lines 270-279)  
**Issue**: Logger metadata uses atom keys while killmail data uses string keys  
**Context**: The enrichment functions log killmail IDs but attempt to access them with atom keys (`:killmail_id`) when the actual data uses string keys.  
**Fix**: Use `Map.get(killmail, "killmail_id")` consistently with string keys  
**Status**: COMPLETED - Fixed 3 Logger calls to consistently use string key "killmail_id" instead of mixed atom/string access

## 6. Duplicated Test Data Setup
**File**: `test/wanderer_kills/subscriptions/webhook_notifier_test.exs` (lines 12-26)  
**Issue**: Subscription map and kills list duplicated across multiple tests  
**Context**: The same test data structures are defined in multiple test cases, violating DRY principles.  
**Fix**: Extract to a `setup` block that adds data to the test context

## 7. Brittle Header Order Assertions
**File**: `test/wanderer_kills/subscriptions/webhook_notifier_test.exs` (lines 34-37, 139-142)  
**Issue**: Tests assert exact header order which can fail if order changes  
**Context**: HTTP headers can be sent in any order. Testing exact order makes tests fragile.  
**Fix**: Check header presence without order dependency, possibly using pattern matching or converting to a map

## 8. Incorrect Zero-Call Mox Expectations
**File**: `test/wanderer_kills/subscriptions/webhook_notifier_test.exs` (lines 84-88, 108-112)  
**Issue**: Using `Mox.expect` with 0 invocations is undocumented behavior  
**Context**: Tests verify that no HTTP calls are made for nil/empty URLs using `expect(:post, 0, ...)`.  
**Fix**: Use `Mox.stub` instead, or rely on `verify_on_exit!` without setting up expectations