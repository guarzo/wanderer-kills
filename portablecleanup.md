# 🧼 WandererKills Codebase Cleanup Plan

## 🔁 Duplicate & Redundant Code Elimination

- [ ] 🔍 "Refactor `lib/wanderer_kills/cache/helper.ex` to extract reusable patterns across character, corporation, alliance, ship type, and system cache operations into a `defmacro __using__` or helper module to reduce boilerplate."
- [ ] ✂️ "Delete duplicated `parse_time/1` logic from both `Clock` and `Killmail` utilities if present; centralize time parsing into a single Clock helper."
- [x] 🧹 "Remove `WandererKills.Infrastructure.Clock.system_time/1` or replace usages with `System.system_time/1` unless mocking is a future concern."

## 🧱 Architectural & Structural Improvements

- [x] 📁 "Move `lib/wanderer_kills/infrastructure/config.ex` to `lib/wanderer_kills/config.ex` or `lib/wanderer_kills/support/config.ex` to align with Elixir idioms and reduce overly deep nesting."
- [x] 🧳 "Merge `esi/data_fetcher.ex` and `esi/client.ex` into one file to reduce indirection. These currently act as thin wrappers over one another."
- [ ] 🗃️ "Rename `lib/wanderer_kills/core.ex` to `wanderer_kills.ex` if it’s intended as the primary public API. Otherwise, move exported functions to appropriate domains."
- [x] 🏗️ "Migrate from Plug.Router to Phoenix Router for better organization, pipelines, and consistency with WebSocket endpoint architecture."
- [ ] 🧩 "Unify HTTP client fallback logic between `Http.ClientProvider`, `Http.Client`, and `Http.Util`. Currently, fallback/override logic is spread across 3 layers."

## 🧼 Simplification of Logic

- [ ] 🧠 "Simplify `system_add_killmail/2` logic in Cache.Helper by switching from read+write to `Cachex.update` or `Cachex.transaction` to reduce race conditions and multiple reads."
- [ ] 🧪 "Replace custom `Retry.retry_http_operation/2` logic with `Task.async_stream/3` where applicable, especially in `get_killmails_batch` or batch processing code."

## ⚙️ Refactoring Config Access

- [x] 🧭 "Replace all `Config.cache().x`, `Config.retry().y` calls with a simple `Application.get_env(:wanderer_kills, ...)` alias if you're not using runtime reloads."
- [x] 🧱 "Move retry delay/backoff constants (base delay, factor, etc.) to `Retry` module constants rather than defining in both `Config` and `Retry`."

## 🗃️ File & Module Reorganization

- [x] 🧹 "Move all `behaviours/` files under their associated domain folders (e.g., move `behaviours/data_fetcher.ex` into `esi/`, `killmails/`, etc.) to reduce orphaned interface files."
- [ ] 🧳 "Move `application.ex`, `core.ex`, and `kill_store.ex` into a dedicated `lib/wanderer_kills/app/` directory or refactor into `WandererKills.Application`, `WandererKills.Core`, etc. to reduce root module sprawl."
- [x] 🔄 "Consolidate `lib/wanderer_kills/killmails/parser.ex`, `enricher.ex`, `coordinator.ex`, etc. into a single `killmails/pipeline/` subfolder to reflect linear data pipeline."
- [x] 🧹 "Review single-file directories like `infrastructure/` and flatten where appropriate (e.g., merge with root or `support/`); deep nesting is unnecessary for small submodules."

## 📊 Testing Improvements

- [ ] 🧪 "Create integration tests for the `Cache.Helper.system_*` functions to validate system fetch/killmail tracking and cache coordination logic."
- [ ] 🔁 "Extract test support logic in `test/support/helpers.ex` into domain-specific helpers (`test/support/cache_helpers.ex`, `test/support/http_helpers.ex`) to simplify test setup."

## ⚠️ Unnecessary Complexity Removal

- [ ] 🚮 "Remove unused PubSub topics or consolidate topic naming in a `PubSub.TopicBuilder` module to avoid repeating `zkb:system:#{id}:detailed` in multiple places."
- [ ] 🚧 "Evaluate whether `Infrastructure.BatchProcessor` is adding value over `Task.Supervisor.async_stream/3` directly; currently duplicates logic while adding little abstraction."

## 💎 Idiomatic Elixir Cleanup

- [ ] 🧼 "Replace all `case` blocks with `with` in sequential control flow chains in `esi/data_fetcher.ex`, especially when wrapping `Helper.get_or_set`."
- [ ] 🧪 "Replace `if killmail_id do ... else nil` pattern in `cache_killmails_for_system` with a single `Enum.filter_map` to eliminate side effects inside map."
