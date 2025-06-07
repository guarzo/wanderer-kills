- [ ] **Unify killmail store implementations**  
  Remove the duplicate `lib/wanderer_kills/kill_store.ex` module and update all references to use the single `lib/wanderer_kills/killmails/store.ex` implementation, eliminating redundancy. :contentReference[oaicite:0]{index=0}

- [ ] **Eliminate legacy CSV update pipeline**  
  Delete the `update_ship_types/1`, `download_csv_files/1`, `parse_ship_type_csvs/1`, and related helper functions in `lib/wanderer_kills/core/csv.ex` (the “Legacy Ship Type/Group Parsers” section), migrating any remaining CSV parsing into a dedicated `CsvHelpers` module. :contentReference[oaicite:1]{index=1}

- [ ] **Consolidate caching wrappers**  
  Merge the domain-specific cache modules (`WandererKills.Cache.ESI`, `Cache.ShipTypes`, and `Cache.Systems`) into a single `WandererKills.Cache.Helper` (or into `Core.CacheUtils`), and remove the separate wrapper modules to centralize TTL logic and namespace handling. :contentReference[oaicite:2]{index=2}

- [ ] **Clean up Docker and devcontainer configs**  
  Consolidate the two `Dockerfile` and `docker-compose.yml` files by keeping production-ready definitions at the project root and moving development-specific overrides under `.devcontainer/`, removing any duplicate service definitions. :contentReference[oaicite:3]{index=3}

- [ ] **Abstract common HTTP client logic**  
  Refactor `lib/wanderer_kills/esi/client.ex` and `lib/wanderer_kills/zkb/client.ex` to share a single HTTP request pipeline based on the `WandererKills.Core.Behaviours.HttpClient` behaviour, extracting duplicated retry and parsing code into `Core.Http.Client`. :contentReference[oaicite:4]{index=4}

- [ ] **Remove dead code via Xref**  
  Run `mix xref unreachable` to identify and delete any modules that are no longer referenced (e.g., unused constants in `Core.Constants` or orphaned utility modules), cleaning out dead code. :contentReference[oaicite:5]{index=5}

- [ ] **Adopt domain-driven directory structure**  
  Restructure `lib/wanderer_kills/` into clear contexts—e.g., `Cache`, `ESI`, `ZKB`, `Preloader`, `Killmails`—and collapse the `core/` directory into context modules to reduce indirection. :contentReference[oaicite:6]{index=6}

- [ ] **Consolidate test helpers**  
  Merge overlapping test helper modules (`test/support/cache_helpers.ex` and `test/shared/cache_key_test.exs`) into a single `test/support` helper and remove duplicated test cases. :contentReference[oaicite:7]{index=7}

- [ ] **Simplify clock utilities**  
  In `Core.Clock`, remove compatibility branches for configurable `:clock` overrides and deprecate the `get_system_time_with_config/1` complexity, defaulting to `DateTime.utc_now()` and `System.system_time/1`. :contentReference[oaicite:8]{index=8}

- [ ] **Prune unused config entries**  
  Clean up `config/*.exs` by removing commented-out or unused keys (e.g., legacy ESI CSV config), and consolidate flat config keys back into nested scopes where appropriate for clarity. :contentReference[oaicite:9]{index=9}
