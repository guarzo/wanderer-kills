# WandererKills Refactoring Plan

Based on the code review conducted on 2025-06-10, this document outlines a structured approach to address identified issues while minimizing risk and maximizing code quality improvements.

**Last Updated**: 2025-06-10 (Phase 1 & 2 Substantially Complete)

## Overview

The refactoring will be executed in phases, prioritizing high-impact changes that improve maintainability and reduce technical debt. Each phase includes specific tasks, testing requirements, and success criteria.

## Progress Summary

### ✅ Completed Tasks (Phase 1 - Critical Issues)
1. **Store Consolidation** ✅ - Merged duplicate ETS stores into unified `WandererKills.Storage.KillmailStore`
2. **Error Standardization** ✅ - Implemented consistent `{:ok, result}` / `{:error, %Error{}}` pattern across core modules
3. **HTTP Client Centralization** ✅ - Replaced direct Req usage with centralized HTTP client, added POST support
4. **Store Behaviours** ✅ - Added behaviour definitions for better testability

### ✅ Completed Tasks (Phase 2 - Naming Standardization)
5. **Killmail Naming Standardization** ✅ - Changed "kill" to "killmail" throughout codebase
6. **Fetch/Get Naming Conventions** ✅ - Implemented get_* (local) vs fetch_* (external) pattern
7. **System ID Standardization** ✅ - Use system_id internally, handle solar_system_id at API boundaries

### ✅ Additional Runtime Fixes
8. **Ship Name Enrichment Fix** ✅ - Fixed CSV ship type loading (86 → 1000s) and added ESI fallback
9. **Logging Cleanup** ✅ - Reduced verbose info-level logs to debug level

### 📋 Remaining Tasks (Lower Priority)
- **Consolidate Normalization Logic** - Merge scattered normalization modules
- **Add _async Suffixes** - Clarify asynchronous operations
- **Centralize Configuration Access** - Single config access point

## Phase 1: Critical Issues (Week 1-2)

### 1.1 Consolidate Store Modules 🔴
**Priority**: High  
**Effort**: Large (8-12 hours)  
**Risk**: Medium

**Current State**:
- Two separate store implementations: `WandererKills.Killmails.Store` and `WandererKills.App.KillStore`
- Duplicate ETS table management
- Unclear which store to use when

**Target State**:
- Single unified store module with optional event streaming
- Clear API for both basic storage and event-driven scenarios
- Backward compatibility during transition

**Implementation Steps**:
1. Create new `WandererKills.Storage.KillmailStore` behaviour
2. Implement unified store combining both functionalities
3. Add feature flags for event streaming
4. Migrate existing usages incrementally
5. Deprecate old modules
6. Remove deprecated modules after verification

**Testing Requirements**:
- Unit tests for all storage operations
- Integration tests for event streaming
- Performance benchmarks to ensure no regression
- Concurrent access tests

### 1.2 Standardize Error Handling 🔴
**Priority**: High  
**Effort**: Medium (6-8 hours)  
**Risk**: Low

**Current Patterns to Replace**:
```elixir
# Replace these:
:error
{:error, "string message"}
{:ok, :kill_older}

# With:
{:error, %WandererKills.Error{type: :not_found, message: "..."}}
{:ok, result}
```

**Implementation Steps**:
1. Define comprehensive error types in `WandererKills.Error`
2. Create error helper functions
3. Update each module systematically
4. Add dialyzer specs for all public functions
5. Update tests to match new error patterns

**Modules to Update** (in order):
1. HTTP clients (establish pattern)
2. Store modules
3. Pipeline modules
4. Controllers and API responses

### 1.3 Fix HTTP Client Duplication 🔴
**Priority**: High  
**Effort**: Small (2-3 hours)  
**Risk**: Low

**Target Changes**:
- Replace direct `Req` usage in `subscription_manager.ex`
- Use `WandererKills.Http.Client` for all HTTP calls
- Add webhook-specific configuration to HTTP client

**Implementation**:
1. Add webhook support to `Http.Client` behaviour
2. Implement webhook methods in HTTP client
3. Update subscription_manager to use client
4. Add proper retry logic and timeouts
5. Update tests with mocked client

## Phase 2: Naming Standardization (Week 3)

### 2.1 Killmail vs Kill Terminology 🟡
**Priority**: Medium  
**Effort**: Medium (4-6 hours)  
**Risk**: Low

**Standardization Rules**:
- Always use `killmail` (never just `kill`)
- Update all function names, variables, and documentation
- Keep `kill_id` only where it matches external API field names

**Automated Approach**:
1. Create migration script to identify all occurrences
2. Generate refactoring commands
3. Update in batches by module
4. Run full test suite after each batch

### 2.2 Fetch vs Get Convention 🟡
**Priority**: Medium  
**Effort**: Small (2-3 hours)  
**Risk**: Low

**Convention**:
- `get_*` - Local operations (cache, ETS, memory)
- `fetch_*` - External API calls
- `find_*` - Search operations with criteria
- `list_*` - Return multiple items

**Implementation**:
1. Document convention in CLAUDE.md
2. Create credo rule to enforce
3. Refactor module by module
4. Update function specs

### 2.3 System ID Standardization 🟡
**Priority**: Medium  
**Effort**: Small (1-2 hours)  
**Risk**: Low

**Target**:
- Use `system_id` everywhere in internal code
- Handle `solar_system_id` at API boundaries only
- Create field mapping utilities

## Phase 3: Architectural Improvements (Week 4)

### 3.1 Consolidate Normalization Logic 🟡
**Priority**: Medium  
**Effort**: Medium (4-6 hours)  
**Risk**: Medium

**Current State**:
- Logic spread across Normalizer, Transformations, FieldNormalizer

**Target State**:
- Single `WandererKills.Killmails.Normalization` module
- Clear sub-modules for different normalization types
- Composable normalization pipeline

**Structure**:
```
Normalization/
├── normalization.ex (main API)
├── field_normalizer.ex (field-level)
├── structural_normalizer.ex (structure)
└── value_normalizer.ex (values)
```

### 3.2 Add Store Behaviours 🟡
**Priority**: Medium  
**Effort**: Medium (3-4 hours)  
**Risk**: Low

**Implementation**:
1. Define `WandererKills.Storage.Behaviour`
2. Add callbacks for all store operations
3. Implement behaviour in store modules
4. Create mock implementation for tests
5. Update all tests to use mocks

### 3.3 Async Operation Naming 🟡
**Priority**: Medium  
**Effort**: Small (1-2 hours)  
**Risk**: Low

**Convention**:
- Add `_async` suffix to all async operations
- Document async behavior in function docs
- Return `{:ok, task}` or `{:ok, :enqueued}`

## Phase 4: Configuration & Documentation (Week 5)

### 4.1 Centralize Configuration 🟢
**Priority**: Low  
**Effort**: Small (2-3 hours)  
**Risk**: Low

**Changes**:
- All config access through `WandererKills.Config`
- Validated configuration at startup
- Environment-specific overrides
- Runtime configuration support

### 4.2 Documentation Updates 🟢
**Priority**: Low  
**Effort**: Medium (3-4 hours)  
**Risk**: None

**Deliverables**:
- Update CLAUDE.md with new patterns
- Create ARCHITECTURE.md
- Add module documentation
- Update API documentation

## Testing Strategy

### For Each Refactoring:
1. **Before Changes**:
   - Run full test suite, record coverage
   - Run performance benchmarks
   - Document current behavior

2. **During Changes**:
   - Write tests for new behavior first
   - Refactor incrementally
   - Run tests after each change

3. **After Changes**:
   - Verify coverage maintained/improved
   - Run performance benchmarks
   - Test in staging environment

### Regression Testing:
- Full API integration tests
- WebSocket functionality tests
- Load testing for performance
- Backward compatibility tests

## Risk Mitigation

### Feature Flags:
```elixir
# config/config.exs
config :wanderer_kills,
  use_unified_store: false,
  use_new_error_format: false
```

### Rollback Plan:
1. Each phase in separate PR
2. Feature flags for major changes
3. Backward compatibility layer
4. Gradual rollout to production

## Success Metrics

### Code Quality:
- [ ] Credo score improvement (target: 95%+)
- [ ] Dialyzer warnings eliminated
- [ ] Test coverage maintained (85%+)
- [ ] Reduced code duplication (<5%)

### Performance:
- [ ] No regression in API response times
- [ ] Memory usage stable or improved
- [ ] ETS operations performance maintained

### Developer Experience:
- [ ] Reduced onboarding time for new devs
- [ ] Clearer module boundaries
- [ ] Consistent patterns throughout

## Timeline

**Week 1-2**: Phase 1 (Critical Issues)
**Week 3**: Phase 2 (Naming Standardization)
**Week 4**: Phase 3 (Architectural Improvements)
**Week 5**: Phase 4 (Configuration & Documentation)
**Week 6**: Final testing, performance verification, and deployment

## Next Steps

1. Review and approve this plan
2. Create tracking issues for each task
3. Set up feature flags infrastructure
4. Begin Phase 1 implementation
5. Schedule weekly progress reviews

---

*Plan created: 2025-06-10*  
*Estimated completion: 6 weeks*  
*Total effort: ~40-50 hours*