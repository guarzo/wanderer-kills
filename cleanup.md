
- [ ] “Refactor ESI fetchers (character_fetcher.ex, killmail_fetcher.ex, type_fetcher.ex) and WandererKills.ESI.Client to use a shared DataFetcher pipeline or the HttpClient behaviour directly, deleting bespoke fetcher modules if 
their logic is subsumed by a generic solution.”
- [ ] “Migrate the core ETS GenServer caches to Cachex: update your application supervisor to start Cachex instances for each cache namespace, remove all manual ETS table-creation and GenServer modules in `Core.Cache`, and delete the old cache supervision code.”
- [ ] “Replace every `Core.Cache.put/3`, `put_with_ttl/4`, and `get/2` call in domain modules with `Cachex.put/4` and `Cachex.get!/3`, sourcing TTL values via `Config.cache_ttl/1` and converting seconds to milliseconds as needed.”
- [ ] “Remove the manual cleanup scheduler and `cleanup_expired_entries/0` family of functions: delete the scheduled GenServer invocation, supporting helper functions, and their tests, relying instead on Cachex’s built-in TTL eviction.”
- [ ] “Eliminate the `:cache_stats` ETS table and custom stats code: implement `Cachex.handle_event/2` callbacks or Telemetry handlers to capture hits/misses, and remove all ETS-based statistics modules and tests.”
- [ ] “Consolidate per-entity ETS tables into a single Cachex instance with multiple namespaces (e.g. `:esi`, `:ship_types`, `:systems`): define namespaced caches in your config, set per-namespace TTLs, and remove individual ETS table definitions.”
- [ ] “Standardize cache key formatting by creating a `key(type, id)` helper in each domain cache wrapper (e.g. `WandererKills.Cache.ShipTypes.key/1`) and refactor all modules to call these helpers instead of using raw tuples or integers.”
- [ ] “Extract domain-specific cache wrappers (e.g. `WandererKills.Cache.ShipTypes`, `WandererKills.Cache.Systems`) that encapsulate Cachex operations—`get_or_set`, TTL logic, and key generation—so business logic never interacts directly with Cachex.”
- [ ] “Update your test helpers to drop ETS-based teardown: use `Cachex.clear/1` for each namespace in `TestHelpers.clear_all_caches/0`, and adjust existing tests to reference Cachex caches instead of ETS tables.”
- [ ] “Audit the entire codebase for any remaining direct ETS calls (`:ets.insert`, `:ets.lookup`, etc.) or manual caching logic, and refactor them to use the new Cachex-based wrappers.”
- [ ] “Write integration tests to validate the Cachex migration preserves behavior: cover cache hits, misses, TTL expirations, and fallback functions for critical modules like ESI fetchers and ShipType updaters.”  

