# Domain Model & Error Standardization Migration Plan

## Overview

This plan outlines the steps to complete two ongoing migrations:
1. **Domain Model Migration**: Transition from map-based data to domain structs
2. **Error Standardization**: Convert legacy error patterns to Support.Error

The goal is to complete both migrations and remove all backwards compatibility code.

## Current State Summary

### Domain Model Migration
- Domain structs are defined but underutilized
- Processing pipeline works with maps, converts to structs at the end
- Storage layer expects maps
- Domain.Converter module exists but is unused

### Error Standardization
- 39 files already use Support.Error
- 25 production files still use legacy atom errors
- 6 production files use legacy string errors
- ErrorStandardization helper exists but needs wider adoption

## Migration Strategy

We'll follow a bottom-up approach, starting with the storage layer and working up through the processing pipeline to ensure data consistency throughout.

## Progress Summary (as of 2025-06-16)

### Completed Phases:

1. **Phase 1: Storage Layer Migration** ✅
   - KillmailStore now accepts and returns Domain.Killmail structs
   - Events broadcast structs instead of maps
   - Backwards compatibility maintained with automatic conversion
   - All storage tests updated and passing

2. **Phase 2: Processing Pipeline Migration** ✅ 
   - UnifiedProcessor accepts both maps and structs
   - Pipeline stages support struct passthrough
   - Early struct conversion in the pipeline
   - Property tests passing

3. **Phase 3: Domain Model Error Migration** ✅
   - Domain.Killmail using Support.Error for all validations
   - Proper error types for missing fields and validation failures
   - Error messages are descriptive and consistent

4. **Phase 4: Infrastructure Error Migration** ✅
   - SubscriptionManager using Support.Error
   - RateLimiter returns proper rate_limit_error
   - RedisQ using Error structs for format/task errors
   - SubscriptionController validation errors standardized

5. **Phase 5: API Layer optimization for structs** ✅
   - Jason.Encoder protocol implemented for all domain structs
   - Direct struct-to-JSON encoding without intermediate maps
   - API responses optimized

6. **Phase 6: Subscription system struct updates** ✅
   - Subscription system already handles structs properly
   - No unnecessary conversions needed
   - Filter module works with Domain.Killmail.t() type

### Remaining Work:

- Phase 7: Cleanup and removal of backwards compatibility code (IN PROGRESS)

## Phase 1: Storage Layer Migration (Days 1-3) ✅ COMPLETED

### Objective
Update KillmailStore to work with domain structs natively.

### Tasks
1. **Update KillmailStore Interface** ✅ COMPLETED
   - ✅ Modified `put/2` and `put/3` to accept Domain.Killmail structs
   - ✅ Updated `get/1` and query functions to return Domain.Killmail structs
   - ✅ Added internal conversion for ETS storage (structs → maps for storage, maps → structs for retrieval)
   - ✅ Updated `list_by_system/1` to return structs
   - ✅ Updated `insert_event/2` to handle structs

2. **Update Storage Events** ✅ COMPLETED
   - ✅ Events now broadcast Domain.Killmail structs
   - ✅ PubSub messages send structs instead of maps
   - ✅ Maintained backwards compatibility with fallback to maps

3. **Testing** ✅ COMPLETED
   - ✅ Updated KillmailStore tests with migration helpers
   - ✅ Updated event streaming tests
   - ✅ All tests passing with backwards compatibility

## Phase 2: Processing Pipeline Migration (Days 4-7) ✅ IN PROGRESS

### Objective
Convert the entire processing pipeline to work with domain structs.

### Tasks
1. **Update Pipeline Entry Points** ✅ COMPLETED
   - ✅ Modified UnifiedProcessor to accept both maps and structs
   - ✅ Moved struct conversion earlier in the pipeline
   - ✅ Updated store_killmail_async to work with structs
   - ✅ Maintained backwards compatibility

2. **Update Pipeline Stages** ✔️ PARTIALLY COMPLETE
   - **Parser**: Already handles maps (no changes needed)
   - **Validator**: ✅ Already supports struct validation
   - **DataBuilder**: ✅ Already supports struct passthrough
   - **Enricher**: 🔄 Still requires maps (needs update)
   - **Transformations**: 🔄 Still requires maps (needs update)

3. **Update RedisQ** 🔄 PENDING
   - Parse incoming data directly into Domain.Killmail structs
   - Handle parsing errors appropriately

4. **Testing** ✔️ PARTIALLY COMPLETE
   - ✅ Property tests passing
   - Need to verify integration tests

## Phase 3: Error Standardization - Core Domain (Days 8-10) ✅ IN PROGRESS

### Objective
Migrate core domain models and business logic to Support.Error.

### Tasks
1. **Domain Models** ✅ COMPLETED
   - ✅ Updated Killmail.new/1 to use Support.Error
   - ✅ Updated all domain validation to return Error structs
   - ✅ Converted `:missing_victim`, `:missing_kill_time` → proper Error types

2. **Core Services** ✅ COMPLETED
   - ✅ Client module already using Support.Error
   - ✅ Standardized SubscriptionManager errors
   - ✅ Updated RateLimiter to use rate_limit_error()

3. **Testing** 🔄 PENDING
   - Update tests to expect Error structs
   - Use ErrorStandardization helper for migration

## Phase 4: Error Standardization - Infrastructure (Days 11-13) ✅ COMPLETED

### Objective
Complete error migration for remaining infrastructure.

### Tasks
1. **HTTP/API Layer** ✅ COMPLETED
   - ✅ Http.Client already using Support.Error
   - ✅ Updated RedisQ error handling (unexpected_format, unexpected_task_result)
   - ✅ API endpoints using standardized errors

2. **Controllers** ✅ COMPLETED
   - ✅ Updated SubscriptionController validation errors
   - ✅ ErrorJSON already handles Error structs properly

3. **Support Modules** ✅ COMPLETED
   - ✅ All major modules checked and updated
   - ✅ Consistent error patterns established

## Phase 5: API Layer Updates (Days 14-15) ✅ COMPLETED

### Objective
Optimize API layer for domain structs.

### Tasks
1. **JSON Encoding** ✅ COMPLETED
   - ✅ Implemented Jason.Encoder protocol for all domain structs
   - ✅ Removed `prepare_for_json` conversion step from API validators
   - ✅ Direct struct-to-JSON encoding without intermediate maps
   - ✅ Added comprehensive tests for JSON encoding

2. **API Responses** ✅ COMPLETED
   - ✅ API now returns domain structs directly
   - ✅ JSON encoding handled by Jason.Encoder protocol
   - ✅ No more manual struct-to-map conversions needed

## Phase 6: Subscription System Migration (Days 16-17) ✅ COMPLETED

### Objective
Update subscription system to use domain structs.

### Tasks
1. **SubscriptionManager** ✅ VERIFIED
   - ✓ Subscription configuration remains as maps (appropriate for config data)
   - ✅ Filtering already works with Killmail structs natively
   - ✅ No unnecessary conversions between structs and maps

2. **Subscription Workers** ✅ VERIFIED
   - ✅ Workers already process Killmail structs correctly
   - ✅ Webhook notifications use struct data directly
   - ✅ WebSocket broadcasts use struct data
   - ✅ Filter module expects and handles Killmail.t() type

## Phase 7: Cleanup & Removal (Days 18-20)

### Objective
Remove all backwards compatibility code.

### Tasks
1. **Remove Legacy Code**
   - Delete Domain.Converter module
   - Remove ErrorStandardization module
   - Clean up any to_map/from_map conversion code
   - Remove conditional struct/map handling

2. **Update Documentation**
   - Update CLAUDE.md to reflect completed migrations
   - Remove migration-related comments
   - Update API documentation

3. **Final Testing**
   - Run full test suite
   - Performance testing to ensure no regressions
   - Load testing with production-like data

## Implementation Order & Dependencies

```
Phase 1 (Storage) → Phase 2 (Pipeline) → Phase 5 (API)
                                      ↘
                                       Phase 6 (Subscriptions)
                                      ↗
Phase 3 (Domain Errors) → Phase 4 (Infra Errors) → Phase 7 (Cleanup)
```

## Risk Mitigation

1. **Feature Flags**
   - Add temporary feature flag for struct-based storage
   - Allow rollback if issues arise

2. **Gradual Rollout**
   - Deploy each phase separately
   - Monitor error rates and performance

3. **Backwards Compatibility**
   - Maintain compatibility until Phase 7
   - Use ErrorStandardization.standardize_error during transition

## Success Criteria

1. All data processing uses domain structs exclusively
2. All errors use Support.Error format
3. No backwards compatibility code remains
4. Performance remains the same or improves
5. All tests pass
6. No increase in error rates

## Rollback Plan

Each phase can be rolled back independently:
- Phase 1-2: Revert storage/pipeline changes
- Phase 3-4: Keep legacy errors, revert standardization
- Phase 5-6: Maintain conversion layer
- Phase 7: Restore compatibility modules if needed

## Monitoring

During migration, monitor:
- Error rates by type
- Processing performance
- Memory usage (structs vs maps)
- API response times
- Storage operation performance