# Code Review - WandererKills Codebase

## Executive Summary

This document presents a comprehensive review of the WandererKills codebase, focusing on code duplication, naming inconsistencies, pattern variations, and architectural issues. The codebase is generally well-structured with good supervision tree design and domain boundaries, but would benefit from standardization efforts.

## 1. Code Duplication Issues

### 1.1 Duplicate Store Modules 🔴 **High Priority**

**Issue**: Two separate modules implement similar killmail storage functionality:
- `WandererKills.Killmails.Store` - Basic ETS storage
- `WandererKills.App.KillStore` - ETS storage with event streaming

**Details**:
```elixir
# Both modules have similar initialization:
# Store (lib/wanderer_kills/killmails/store.ex)
@killmail_table :killmails
@system_killmails_table :system_killmails
@system_fetch_timestamps_table :system_fetch_timestamps

# KillStore (lib/wanderer_kills/app/kill_store.ex)
@killmails_table :killmails
@system_killmails_table :system_killmails
@system_fetch_timestamps_table :system_fetch_timestamps
# Plus additional tables for event streaming
```

**Impact**: Confusion about which store to use, potential data inconsistency, maintenance overhead.

**Recommendation**: Consolidate into a single store module with optional event streaming capabilities.

### 1.2 HTTP Client Duplication 🟡 **Medium Priority**

**Issue**: Direct `Req` usage in `subscription_manager.ex` instead of using centralized HTTP client.

**Found in**:
- `/app/lib/wanderer_kills/subscription_manager.ex` (lines 442-446, 483-487)

**Pattern**:
```elixir
# Duplicated in subscription_manager.ex
case Req.post(subscription.callback_url,
       json: payload,
       headers: [{"Content-Type", "application/json"}],
       receive_timeout: 10_000
     ) do
  {:ok, %Req.Response{status: status}} when status in 200..299 ->
    Logger.info(...)
  {:ok, %Req.Response{status: status}} ->
    Logger.warning(...)
  {:error, reason} ->
    Logger.error(...)
end
```

**Recommendation**: Use the centralized `Http.Client` module for all HTTP requests.

### 1.3 Normalization Logic Duplication 🟡 **Medium Priority**

**Issue**: Similar normalization functionality spread across three modules:
- `/app/lib/wanderer_kills/killmails/pipeline/normalizer.ex`
- `/app/lib/wanderer_kills/killmails/transformations.ex`
- `/app/lib/wanderer_kills/killmails/field_normalizer.ex`

**Recommendation**: Consolidate normalization logic into a single module with clear responsibilities.

## 2. Naming Inconsistencies

### 2.1 Killmail vs Kill 🟡

**Inconsistent usage across the codebase**:
- `fetch_killmail` vs `get_killmail`
- `store_killmail` vs `put`
- `kill_id` vs `killmail_id`
- `kill_data` vs `killmail`

**Recommendation**: Standardize on `killmail` throughout the codebase.

### 2.2 Fetch vs Get 🟡

**Different patterns for similar operations**:
- `fetch_killmail` (ZkbClient) vs `get_killmail` (ESI.DataFetcher)
- `fetch_system_killmails` vs `get_system_kill_count`
- `fetch_events` vs `get_client_offsets`

**Recommendation**: 
- Use `get_` for local/cache operations
- Use `fetch_` for external API calls

### 2.3 System ID References 🟡

**Inconsistent field names**:
- `solar_system_id` vs `system_id`
- `systemID` (in URLs) vs `system_id` (in code)

**Recommendation**: Standardize on `system_id` in code, handle external API variations at boundaries.

## 3. Pattern Inconsistencies

### 3.1 Error Handling 🔴 **High Priority**

**Multiple error return patterns**:
```elixir
# Pattern 1: Atom
:error

# Pattern 2: Tagged tuple with string
{:error, "Something went wrong"}

# Pattern 3: Tagged tuple with custom error
{:error, %Error{type: :not_found, message: "..."}}

# Pattern 4: Special returns
{:ok, :kill_older}
```

**Recommendation**: Standardize on `{:ok, result}` / `{:error, %Error{}}` pattern throughout.

### 3.2 Function Return Values 🟡

**Inconsistent return patterns**:
- Some functions return bare values, others wrap in `{:ok, value}`
- Special returns like `{:ok, :kill_older}` vs `:older`

**Recommendation**: Always use tagged tuples for consistency and error handling.

### 3.3 Async Operation Naming 🟡

**Inconsistent async naming**:
- `store_killmail_async` - explicit async suffix
- Other async operations don't indicate async nature

**Recommendation**: Use `_async` suffix for all asynchronous operations.

## 4. Architectural Issues

### 4.1 Module Organization 🟡

**Issues**:
- Enrichment logic split between `Pipeline.Enricher` and `Enrichment.BatchEnricher`
- HTTP functionality split between `Http.Client` and `Http.Base`
- Some cache operations in `Cache.Helper`, others directly in modules

**Recommendation**: 
- Single responsibility per module
- Clear module boundaries
- Consistent abstraction levels

### 4.2 Behaviour Usage Inconsistency 🟡

**Current state**:
- HTTP clients have behaviours ✅
- Store modules lack behaviours ❌
- Inconsistent mock/test patterns

**Recommendation**: Add behaviours to all modules that have external dependencies or multiple implementations.

### 4.3 Configuration Access 🟡

**Multiple patterns**:
- Some use `Application.get_env`
- Others use `Config` module
- Inconsistent configuration structure

**Recommendation**: Centralize configuration access through the `Config` module.

## 5. Positive Findings ✅

### Well-Implemented Areas

1. **Cache Operations**: Excellently centralized in `Cache.Helper`
2. **Supervision Tree**: Clear OTP structure with proper fault tolerance
3. **Domain Boundaries**: Generally good separation of concerns
4. **Telemetry**: Comprehensive instrumentation throughout
5. **Error Types**: Good use of custom error structs (when used)
6. **Behaviours for External Clients**: All external APIs have behaviours

## 6. Recommendations Summary

### High Priority
1. **Consolidate Store modules** - Merge or clearly separate `Store` and `KillStore`
2. **Standardize error handling** - Use `{:ok, result}` / `{:error, %Error{}}` everywhere
3. **Fix duplicate HTTP client usage** - Use centralized client in subscription_manager

### Medium Priority
1. **Standardize naming conventions**:
   - Always use `killmail` (not `kill`)
   - `get_` for reads, `fetch_` for external calls
   - `system_id` consistently
2. **Add behaviours to Store modules**
3. **Consolidate normalization logic**
4. **Use `_async` suffix consistently**

### Low Priority
1. **Centralize configuration access**
2. **Document module responsibilities**
3. **Add typespecs where missing**

## 7. Impact Assessment

- **Code Duplication**: Currently adds ~20% maintenance overhead
- **Naming Inconsistencies**: Increases onboarding time for new developers
- **Pattern Variations**: Makes code reviews more difficult
- **Overall**: These issues are manageable but addressing them would significantly improve maintainability

## 8. Next Steps

1. Create a refactoring plan prioritizing high-impact, low-risk changes
2. Establish coding standards document
3. Add linting rules to enforce conventions
4. Refactor incrementally with comprehensive testing

---

*Review conducted on: 2025-06-10*
*Codebase version: Current development branch*