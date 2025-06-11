# PR Feedback Task List

## Code Cleanup & Legacy Code Removal

- [ ] **Remove backwards compatibility functions**
  - Location: `lib/wanderer_kills/observability/health_checks.ex:244-255`
  - The `version/0` function is marked as "Backwards compatibility" 
  - Remove this function and update any callers to use `check_health/1` instead
  - Also check for other legacy patterns in:
    - `lib/wanderer_kills/killmails/transformations.ex:73` (legacy field names)
    - `lib/wanderer_kills/killmails/preloader.ex:133` (legacy `killmail_time` fields)
    - `lib/wanderer_kills/support/error_standardization.ex` (entire module for legacy error migration)

## Module & Import Improvements

- [ ] **Add explicit Clock alias in health_checks.ex inner modules**
  - Location: `lib/wanderer_kills/observability/health_checks.ex`
  - Clock.now_iso8601() is used 18 times throughout the file
  - Add `alias WandererKills.Support.Clock` inside each inner defmodule that uses it
  - Affected modules: SystemCheck, CacheCheck, QueueCheck, WebSocketCheck, etc.

## Configuration & Environment

- [ ] **Clean up .env.example file**
  - Location: `.env.example:6-7`
  - ✅ Already removed trailing spaces after equals signs
  - ✅ Already removed LIVE_VIEW_SALT and unnecessary URLs
  - ✅ Already removed SECRET_KEY_BASE

- [ ] **Fix duplicate port configuration**
  - Location: `config/config.exs:4-5`
  - Remove standalone `:port` key from application root
  - Ensure code reads port from `Endpoint.config/2` instead

- [ ] **Replace Code.require_file with import_config**
  - Location: `config/config.exs:87-90`
  - Change `Code.require_file("logger_metadata.exs", __DIR__)` to `import_config "logger_metadata.exs"`
  - Move LoggerMetadata module from config file to `lib/wanderer_kills/logger_metadata.ex`

- [ ] **Consolidate dev.exs configuration blocks**
  - Location: `config/dev.exs:10-15 and line 28`
  - Merge two separate config blocks for WandererKillsWeb.Endpoint into one

## Documentation Updates

- [ ] **Update HTTP client behaviour documentation**
  - Location: `lib/wanderer_kills/http/client_behaviour.ex:2-7`
  - Update @moduledoc to mention both GET and POST operations are supported
  - Current docs incorrectly state "Currently only GET operations are used"

- [ ] **Update client_behaviour.ex documentation**
  - Location: `lib/wanderer_kills/client_behaviour.ex:76,95`
  - Replace "kill updates" with "killmail" for consistency

## API & Routing

- [ ] **Fix smoke test to use versioned API route**
  - Location: `test/integration/api_smoke_test.exs:3-8`
  - Update test to use "/api/v1/ping" instead of "/ping"
  - Add `get "/ping", HealthController, :ping` inside the "/api/v1" scope in router.ex

- [ ] **Remove unnecessary secure browser headers plug**
  - Location: `lib/wanderer_kills_web/router.ex:17-21`
  - Remove `plug(:put_secure_browser_headers)` from API pipeline
  - This adds browser-specific headers not needed for JSON APIs

## Request Handling & Middleware

- [ ] **Replace custom RequestId plug with Phoenix built-in**
  - Location: `lib/wanderer_kills_web/plugs/request_id.ex:14-30`
  - Replace entire custom plug with Phoenix's `Plug.RequestId`
  - Removes uuid dependency and prevents header clobbering
  - Update endpoint.ex to use built-in plug

- [ ] **Fix ApiLogger response size type consistency**
  - Location: `lib/wanderer_kills_web/plugs/api_logger.ex:61-64`
  - Change fallback from "unknown" string to 0 or nil integer
  - Ensures consistent return type for metrics

- [ ] **Add IPv6 support to ApiLogger**
  - Location: `lib/wanderer_kills_web/plugs/api_logger.ex:53-58`
  - Replace pattern matching with `:inet.ntoa(conn.remote_ip)`
  - Handles both IPv4 and IPv6 addresses

## WebSocket Improvements

- [ ] **Fix WebSocket origin security**
  - Location: `lib/wanderer_kills_web/endpoint.ex:20-28`
  - Replace `check_origin: false` with configurable allow-list
  - Add `socket_allowed_origins` to runtime.exs configuration

- [ ] **Fix nil string concatenation in user_socket.ex**
  - Location: `lib/wanderer_kills_web/user_socket.ex:67-74`
  - Check if sanitized_id is nil before concatenation
  - Prevents "nil_" prefix in generated IDs

- [ ] **Make user-agent header lookup case-insensitive**
  - Location: `lib/wanderer_kills_web/user_socket.ex:50-57`
  - Normalize header names to lowercase before comparison

## Health & Monitoring

- [ ] **Enable gzip for static assets**
  - Location: `lib/wanderer_kills_web/endpoint.ex:34-38`
  - Change `gzip: false` to `gzip: true` for production optimization

- [ ] **Fix health controller function calls**
  - Location: `lib/wanderer_kills_web/controllers/health_controller.ex`
  - Line 26: Add options argument to `Monitoring.check_health/1` call
  - Line 57: Add options argument to `Monitoring.get_metrics/1` call
  - Line 26-31: Use calculated status code in json response (503 when unhealthy)

- [ ] **Implement WebSocket controller memoization**
  - Location: `lib/wanderer_kills_web/controllers/websocket_controller.ex:34-37`
  - Cache Info.get_server_status/0 results with short TTL
  - Add explicit 200 status to json response (lines 18-27)

- [ ] **Make WebSocket connection threshold configurable**
  - Location: `lib/wanderer_kills/websocket/info.ex:71-77`
  - Replace hardcoded 1000 connection threshold with config value

## Status & Observability

- [ ] **Implement real status functions**
  - Location: `lib/wanderer_kills/observability/status.ex`
  - Line 39-44: Implement get_last_killmail_time to query KillStore
  - Line 58-63: Implement get_cache_stats with real cache metrics
  - Line 28-34: Fix get_websocket_status to use websocket_connected?/0

- [ ] **Fix Monitoring increment functions**
  - Location: `lib/wanderer_kills/observability/monitoring.ex:157-175`
  - Route increment calls through GenServer cast
  - Update internal state before forwarding to Metrics

- [ ] **Fix WebSocketStats usage in RedisQ**
  - Location: `lib/wanderer_kills/redisq.ex:257-262`
  - Replace KillmailChannel.get_stats() with WebSocketStats module call

## Data Processing & Storage

- [ ] **Fix killmail controller error handling**
  - Location: `lib/wanderer_kills_web/controllers/kills_controller.ex`
  - Line 74-78: Add error handling for fetch_systems_killmails
  - Line 126: Handle {:error, _} from get_killmail to return 404

- [ ] **Fix validator to use system_id**
  - Location: `lib/wanderer_kills/killmails/pipeline/validator.ex:32-38`
  - Update required_fields to use "system_id" instead of "solar_system_id"
  - Add backward compatibility if needed

- [ ] **Fix data_builder killmail_time handling**
  - Location: `lib/wanderer_kills/killmails/pipeline/data_builder.ex:57-66`
  - Pattern match {:ok, time} and store only the time string
  - Remove the if guard

- [ ] **Improve ESI fetcher control flow**
  - Location: `lib/wanderer_kills/killmails/pipeline/esi_fetcher.ex:25-46`
  - Refactor triple-nested case to use `with` expression
  - Add safe hash key access (lines 23-24)

- [ ] **Optimize killmail_store duplicate checking**
  - Location: `lib/wanderer_kills/storage/killmail_store.ex:198-200`
  - Use MapSet instead of list for O(1) lookups
  - Add killmail_id validation (lines 303-304, 320-321, 416-425)
  - Handle error cases in fetch_events (lines 438-446)
  - Replace :ets.foldl with :ets.tab2list + Enum.each (lines 157-163)

## Code Quality & Performance

- [ ] **Review and remove Flow dependency**
  - Location: `mix.exs:66-68`
  - Check if Flow's advanced features are used
  - Replace with Task.async_stream/3 if only simple parallelism needed

- [ ] **Remove phoenix_html dependency**
  - Location: `mix.exs:48-52`
  - Remove unnecessary HTML rendering dependency from API-only project

- [ ] **Fix ETS Manager configuration**
  - Location: `lib/wanderer_kills/app/ets_manager.ex`
  - Line 34-37: Remove redundant {:EXIT, _pid, _reason} handle_info or add trap_exit
  - Line 22-27: Add :read_concurrency and :write_concurrency to ETS options

- [ ] **Fix logger compile-time level check**
  - Location: `lib/wanderer_kills/support/logger.ex:197`
  - Remove explicit Logger.level() check
  - Let Logger handle filtering internally

- [ ] **Fix batch processor debug logging**
  - Location: `lib/wanderer_kills/support/batch_processor.ex:82-85`
  - Use zero-arity function for lazy string evaluation

- [ ] **Fix unsupervised tasks in unified_processor**
  - Location: `lib/wanderer_kills/killmails/unified_processor.ex:240-248`
  - Use Task.Supervisor instead of Task.start
  - Add error handling for task failures

## Config & Settings

- [ ] **Validate PORT environment variable**
  - Location: `config/runtime.exs:55-57`
  - Add validation/sanitization before String.to_integer
  - Handle non-numeric values gracefully

- [ ] **Update EVE Online ID ranges**
  - Location: `lib/wanderer_kills/config.ex:138-142`
  - Update max_character_id to 2_129_999_999
  - Update max_system_id to 34_999_999

- [ ] **Simplify Config module**
  - Location: `lib/wanderer_kills/config.ex`
  - Line 25-33: Simplify nested key access logic
  - Line 154-161: Remove duplicate URL definitions in services()
  - Line 151-152: Refactor to use app() function

## Testing

- [ ] **Fix or remove ineffective cache tests**
  - Location: `test/external/esi_cache_test.exs`
  - Line 112-122: Remove or update "clear cache" test
  - Line 105-108: Change namespace from :ship_types to :groups

- [ ] **Add more test coverage for helpers**
  - Location: `test/integration/api_helpers_test.exs:20-38`
  - Add tests for non-ASCII strings, non-binary types, negative numbers

## Examples & Documentation

- [ ] **Fix example file compilation**
  - Location: `examples/status_logging_example.ex:1-11`
  - Add @moduledoc false or rename to .exs

- [ ] **Update WebSocket examples**
  - Location: `examples/websocket_client.js`
  - Line 8-11: Use ES module import instead of require
  - Line 24-34: Add proper error/timeout handling to connect()
  - Line 152-160: Make disconnect() async and awaitable

- [ ] **Update Python example**
  - Location: `examples/websocket_client.py`
  - Line 1: Make file executable or remove shebang
  - Lines 17,146,166: Update type annotations for Python 3.9+
  - Lines 219-224: Replace bare except with specific exceptions

- [ ] **Update documentation security notes**
  - Location: `examples/README.md:15`
  - Emphasize using wss:// in production instead of ws://

## Markdown & Documentation Formatting

- [ ] **Fix markdown formatting issues**
  - Location: `CODE_REVIEW.md:134-140`
  - Add blank line before code block and specify language
  
- [ ] **Fix CLAUDE.md formatting**
  - Location: `CLAUDE.md:8-126, 182-251`
  - Add blank lines before/after lists and headings
  - Convert emphasized text to proper headings
  - Add newline at end of file

- [ ] **Fix README.md formatting**
  - Various locations: Add language specifiers to code blocks
  - Line 298: Use more formal commit message example
  - Line 361: Convert email to markdown link
  - Line 365: Add missing newline at end of file
  - Lines 47-53, 55-62: Add blank lines around code blocks
  - Lines 341-346: Add blank lines around lists

- [ ] **Fix api-reference.md**
  - Line 321: Add trailing newline

- [ ] **Fix integration-guide.md**
  - Lines 736-761: Add "text" language specifier to code block
  - Line 777: Add missing newline at end
  - Line 776: Simplify "6 months advance notice" wording

## Miscellaneous Improvements

- [ ] **Remove duplicate functions**
  - Location: `lib/wanderer_kills/killmails/transformations.ex:267-272, 301-314`
  - Remove enrich_ship_names/1, keep enrich_with_ship_names/1

- [ ] **Update logging levels**
  - Location: `lib/wanderer_kills/killmails/transformations.ex:378-434`
  - Change cache miss/ESI lookup debug logs to info level
  - Location: `lib/wanderer_kills/systems/killmail_manager.ex:33-36`
  - Change verbose debug logs to trace level

- [ ] **Improve error handling**
  - Location: `lib/wanderer_kills/killmails/time_filters.ex:249-276`
  - Replace broad rescue with specific error types
  - Location: `lib/wanderer_kills_web/channels/killmail_channel.ex:363-391`
  - Return error with invalid system IDs instead of silent filtering
  - Location: `lib/wanderer_kills/cache/helper.ex:186-195`
  - Add DateTime struct guard clause

- [ ] **Fix cache helper value function**
  - Location: `lib/wanderer_kills/cache/helper.ex:127-140`
  - Defer value function execution until after cache miss confirmation

- [ ] **Fix ZKB client fetch_from_cache**
  - Location: `lib/wanderer_kills/killmails/zkb_client.ex:397-404`
  - Add catch-all clause to handle all return values

- [ ] **Fix Client.extract_time_from_zkb pattern matching**
  - Location: `lib/wanderer_kills/client.ex:278-284`
  - Fix function to properly pattern match {:continue, killmail}

- [ ] **Remove redundant wrap_result calls**
  - Location: `lib/wanderer_kills/killmails/enrichment/batch_enricher.ex:241-249`
  - Remove wrap_result calls and delete unused function

- [ ] **Fix metadata duplication**
  - Location: `config/logger_metadata.exs`
  - Lines 320-337: Remove duplicate :file and :line from @dev_metadata
  - Lines 34-45: Remove :response_time, keep only :duration_ms
  - Lines 74-100: Break up large @processing_metadata list
  - Lines 102-150: Partition @websocket_metadata by category

- [ ] **Refactor KillmailManager**
  - Location: `lib/wanderer_kills/systems/killmail_manager.ex`
  - Lines 32-79: Extract responsibilities into helper functions
  - Lines 82-127: Remove Flow.partition, use configurable cutoff time

- [ ] **Update error view responses**
  - Location: `lib/wanderer_kills_web/views/error_view.ex`
  - Lines 1-18: Add numeric status codes to JSON responses
  - Lines 20-28: Remove redundant template_not_found/2 function

- [ ] **Add missing gettext import**
  - Location: `lib/wanderer_kills_web.ex:11-16`
  - Add `import WandererKillsWeb.Gettext` to controller macro

- [ ] **Fix ShipTypes.Updater logging**
  - Location: `lib/wanderer_kills/ship_types/updater.ex:140-147`
  - Pass csv_result as metadata instead of interpolating

- [ ] **Fix Statistics nested case**
  - Location: `lib/wanderer_kills/observability/statistics.ex:306-310`
  - Simplify with pattern matching