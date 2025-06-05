# WandererKills Codebase Cleanup Tasks

## Recent Progress Summary

**Latest Session Completed (Direct Reference Updates Approach):**

**Architecture Decision:** Chose direct reference updates over backward compatibility wrappers for cleaner, maintenance-free code.

---

## HTTP and Network Layer

### HTTP Module Organization

- [x] **HTTP Module Organization Completed**: Removed deprecated `http/retry.ex` that was just delegating to unified `WandererKills.Retry`. All HTTP modules properly consolidated in `http/` directory with clean organization. **Result**: Single source of truth for retry logic, cleaner HTTP module structure.

### Supervisor Simplification

- [x] **Supervisor Simplification Completed**: Cache.Supervisor now uses single unified Cachex instance with namespaced keys (killmails:_, system:_, esi:\*) instead of separate cache processes. **Result**: Reduced OTP process overhead while maintaining logical separation.

## File Structure and Organization

### Web and API Layer

- [ ] **Consolidate web concerns**: Group all web/API concerns under `lib/wanderer_kills_web/` (following Phoenix conventions) instead of having them scattered in root and `web/api/` directories.

## Naming and Consistency

### Function Naming

### File Naming Conventions

- [ ] **Adopt consistent file naming**: Use `snake_case` for all filenames and ensure behaviours vs implementations follow consistent patterns.

## Code Quality and Maintenance

### Configuration Cleanup

- [ ] **Simplify configuration access**: Remove redundant `Config` wrappers for configuration that never changes at runtime.

### Code Simplification

- [ ] **Remove unreachable code paths**: Audit pattern matches for unreachable branches (e.g., in `Cache.Base.get_list/2`) and simplify them.

- [x] **Dependency Cleanup Completed**: Removed unused dependencies `{:httpoison, "~> 2.2"}` and `{:retry, "~> 0.19"}` from mix.exs. App uses Req for HTTP and has its own WandererKills.Retry module. **Result**: Cleaner dependency list, reduced attack surface.

- [ ] **Define public APIs**: Ensure each folder in `lib/wanderer_kills/` has a clear public API module to reduce cross-domain dependencies.

---

## 🏆 Major Cleanup Session Completed

## Summary of Achievements

🎯 **Architecture Decision**: Consistently chose direct reference updates over backward compatibility wrappers for cleaner, maintenance-free code.

📊 **Key Metrics**:

- **100% clean compilation** with `--warnings-as-errors`
- **All deprecated functions** removed
- **All broken module references** fixed
- **Consistent naming conventions** established
- **No unused test modules** found in wrong locations

🚀 **Latest Session Achievements**:

- ✅ **ZKB Module Consolidation**: Unified duplicate ZKB client implementations into single source of truth
- ✅ **HTTP Module Organization**: Removed deprecated HTTP retry module, clean module structure
- ✅ **Supervisor Simplification**: Single unified cache with namespaced keys
- ✅ **Dependency Cleanup**: Removed unused HTTPoison and retry dependencies
- ✅ **Clean Compilation**: 100% success with `--warnings-as-errors` throughout

**Next High-Impact Opportunities**:

- Remove truly unused configuration keys (verified `:http_status_codes` is actively used)
- Consolidate test helpers if they're too granular
- Consider supervisor hierarchy simplification
