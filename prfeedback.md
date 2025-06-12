# PR Feedback Items

- [ ] **Refactor the folder and module layout into clear, domain-driven contexts**
  - Current state: Modules are mostly organized by domain, but some inconsistencies exist (e.g., `esi_fetcher.ex` in the killmails pipeline)
  - Move killmail-processing modules (`pipeline/`, `transformations.ex`, `unified_processor.ex`, `zkb_client.ex`) under `lib/wanderer_kills/killmails/`
  - ESI code is already under `lib/wanderer_kills/esi/` but needs consolidation with pipeline's `esi_fetcher.ex`
  - HTTP clients are properly organized under `lib/wanderer_kills/http/`
  - Ship-types, subscriptions, observability, and systems are already in their respective namespaces
  - Update the supervision tree in `WandererKills.App.Application` to reflect any module moves

- [ ] **Consolidate all caching into the single Cachex instance**
  - Current state: Already using a single Cachex instance (`:wanderer_cache`) with namespace prefixes
  - No legacy per-namespace Cachex instances found - the implementation is already clean
  - `KillmailStore` uses ETS for persistent storage with event streaming, not caching - this should remain separate
  - `EtsManager` manages WebSocket stats tracking, not caching
  - `Cache.Helper` already provides unified interface with namespace support
  - Consider: Review if KillmailStore's ETS storage is still needed or if Cachex with longer TTLs could replace it

- [ ] **Merge the two ESI behaviours into a single behaviour**
  - Current state: Two behaviours exist with different purposes
    - `ESI.ClientBehaviour`: Type-specific methods (get_character, get_corporation, etc.)
    - `ESI.DataFetcherBehaviour`: Generic interface (fetch/1, fetch_many/1, supports?/1)
  - Both are implemented by the same module: `WandererKills.ESI.DataFetcher`
  - Recommendation: Merge into single `ESI.ClientBehaviour` keeping type-specific methods and generic fetch/1
  - Rename `WandererKills.ESI.DataFetcher` to `WandererKills.ESI.Client` for clarity
  - No unused client provider modules found - `Http.ClientProvider` is actively used for HTTP configuration

- [ ] **Simplify configuration by grouping related settings**
  - Current state: Configuration is spread across multiple top-level keys
  - Group under nested keys:
    - `:cache` - All TTL settings (killmails_ttl, systems_ttl, etc.)
    - `:esi` - ESI-related settings (base_url, timeout, retry config)
    - `:http` - HTTP client settings (max_connections, timeout)
    - `:monitoring` - Status intervals, health check settings
    - `:storage` - Event streaming, ETS table configurations
  - Remove defaults from config files - use module attributes for defaults
  - Consolidate environment-specific settings in `runtime.exs` only

- [ ] **Prune dead code and commented-out logic**
  - Remove unused preloader hooks:
    - `maybe_preloader/1` function in application.ex (lines 73-79)
    - `PreloaderSupervisor` references
  - Keep `EtsManager` - it's actively used for WebSocket stats, not replaced by Cachex
  - Review and update example scripts in `examples/` to match current API:
    - Update WebSocket channel topics if changed
    - Ensure REST endpoint examples are current
  - Check `.devcontainer/` for outdated configuration

- [ ] **Standardize error handling using Support.Error**
  - Current state: `Support.Error` module exists with structured error types
  - Error types available: :validation_error, :http_error, :processing_error, :not_found
  - Many modules still use plain tuples or raise exceptions
  - Pipeline stages (Parser, Validator, Enricher) need consistent {:ok, _} | {:error, %Error{}} returns
  - Replace `raise` calls with Error structs in:
    - HTTP client error handling
    - ESI data fetching
    - Killmail processing pipeline
  - Add error metadata for better debugging (killmail_id, system_id, etc.)

- [ ] **Enhance logging with structured metadata**
  - Current state: Mix of plain logging and some structured logging
  - Add metadata to all Logger calls:
    - Killmail operations: killmail_id, hash, system_id
    - ESI calls: entity_type, entity_id, batch_size
    - Cache operations: namespace, key, hit/miss
    - WebSocket: channel, topic, connection_count
  - Remove `IO.puts` from test files - use Logger or ExUnit assertions
  - Configure log levels in runtime.exs:
    - Development: :debug
    - Test: :warning (to reduce noise)
    - Production: :info
  - Consider adding correlation IDs for request tracing

- [ ] **Improve the CI/CD pipeline**
  - Current CI setup in `.github/workflows/ci.yml`:
    - Basic Elixir setup and test running
    - No Docker layer caching
  - Improvements needed:
    - Cache Docker layers for faster builds (buildx cache)
    - Add `mix dialyzer --halt-exit-status` to fail on type warnings
    - Parallelize tests: `mix test --max-failures=1 --partitions=4`
    - Add documentation validation: `mix docs` and check for warnings
    - Cache dependencies between runs (_build and deps directories)
    - Add coverage threshold enforcement
    - Consider matrix testing for multiple Elixir/OTP versions

- [ ] **Audit and extend test coverage**
  - Current coverage gaps identified:
    - `SubscriptionManager` - Core subscription logic needs tests
    - `WebhookNotifier` - HTTP webhook delivery testing
    - `KillmailStore` - ETS storage operations and event streaming
    - ESI batch operations in `DataFetcher`
    - `Broadcaster` - PubSub message distribution
  - Coverage tooling:
    - Mix tasks exist: `mix test.coverage` and `mix test.coverage.ci`
    - Integrate with CI pipeline for automatic reporting
    - Set minimum coverage threshold (e.g., 80%)
  - Test improvements:
    - Add property-based tests for data transformations
    - Test error scenarios and retry logic
    - Mock external services consistently

- [ ] **Revise documentation to remove duplication**
  - Current state: Multiple overlapping documentation files
    - `api-reference.md` - REST API documentation
    - `integration-guide.md` - Similar API docs with examples
    - `performance.md` - Performance considerations
  - Consolidation plan:
    - Merge API docs into single source of truth
    - Generate route documentation from `mix phx.routes`
    - Use `mix docs` for module documentation
  - Update `examples/` directory:
    - Verify WebSocket channel topics match actual implementation
    - Update module names in code examples
    - Add examples for new features (batch operations, webhooks)
  - Consider using OpenAPI/Swagger for API documentation

- [x] **Improve Cachex statistics logging in status reports**
  - Current state: Only logging cache size, memory, and hit rate in periodic status reports
  - Available Cachex stats being collected but not logged:
    - `miss_rate` - Cache miss percentage
    - `eviction_count` - Number of entries evicted
    - `expiration_count` - Number of entries expired
    - `update_count` - Number of cache updates
    - Per-operation counts (get, put, delete operations)
  - Implementation location: `WebSocketStats.log_cache_stats/1` (lines 401-413)
  - Recommendation: Enhance the 5-minute status report to include:
    - Hit/miss ratio trends
    - Eviction and expiration rates
    - Operation counts for performance monitoring
    - Memory efficiency metrics (entries per MB)
  - Consider adding cache performance alerts when hit rate drops below threshold

  - [x] Fix runtime error - 01:36:23.110 file=lib/wanderer_kills/observability/websocket_stats.ex line=389 [info] [RedisQ Stats] Kills processed: 66 | Active systems: 10 | Queue size: 0
01:36:23.114 file=gen_server.erl line=2646 [error] GenServer WandererKills.Observability.WebSocketStats terminating
** (FunctionClauseError) no function clause matching in Float.round/2
    (elixir 1.18.3) lib/float.ex:349: Float.round(0, 1)
    (wanderer_kills 0.1.0) lib/wanderer_kills/observability/websocket_stats.ex:402: WandererKills.Observability.WebSocketStats.log_cache_stats/1
    (wanderer_kills 0.1.0) lib/wanderer_kills/observability/websocket_stats.ex:351: WandererKills.Observability.WebSocketStats.log_stats_summary/1
    (wanderer_kills 0.1.0) lib/wanderer_kills/observability/websocket_stats.ex:278: WandererKills.Observability.WebSocketStats.handle_info/2
    (stdlib 6.2.2) gen_server.erl:2345: :gen_server.try_handle_info/3
    (stdlib 6.2.2) gen_server.erl:2433: :gen_server.handle_msg/6
    (stdlib 6.2.2) proc_lib.erl:329: :proc_lib.init_p_do_apply/3
Last message: :stats_summary
01:36:23.131 file=lib/wanderer_kills/observability/websocke