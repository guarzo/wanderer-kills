# WandererKills Codebase Cleanup Tasks

## Recent Progress Summary

**Latest Session Completed (Direct Reference Updates Approach):**

**Architecture Decision:** Chose direct reference updates over backward compatibility wrappers for cleaner, maintenance-free code.

---


## Naming and Consistency

### Function Naming

### File Naming Conventions

- [ ] **Adopt consistent file naming**: Use `snake_case` for all filenames and ensure behaviours vs implementations follow consistent patterns.

## Code Quality and Maintenance

### Code Simplification

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

**Next High-Impact Opportunities**:

- Remove truly unused configuration keys (verified `:http_status_codes` is actively used)
- Consolidate test helpers if they're too granular
- Consider supervisor hierarchy simplification
- Audit and potentially remove backward compatibility alias modules (Config, Constants, etc.) if usage allows
