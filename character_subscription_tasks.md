# Character-Based Killmail Subscription Implementation Tasks

## Overview
This document outlines the detailed implementation tasks for adding character-based killmail subscriptions to WandererKills. Characters can be tracked as either victims or attackers in killmails.

## Phase 1: Core Infrastructure

### 1.1 Create Character Matching Module
- [x] Create `lib/wanderer_kills/killmails/character_matcher.ex`
- [x] Implement `killmail_has_characters?/2` function
  - [x] Check victim character_id against character list
  - [x] Check all attacker character_ids against character list
  - [x] Return true if any match found
- [x] Implement `extract_character_ids/1` function
  - [x] Extract victim character_id
  - [x] Extract all attacker character_ids
  - [x] Return unique list of all character_ids
- [x] Write comprehensive tests in `test/wanderer_kills/killmails/character_matcher_test.exs`
  - [x] Test victim-only matches
  - [x] Test attacker-only matches
  - [x] Test mixed victim and attacker matches
  - [x] Test no matches
  - [x] Test nil/missing character_ids
  - [x] Test performance with large attacker lists

### 1.2 Update SubscriptionManager Data Model
- [x] Modify `lib/wanderer_kills/subscription_manager.ex`
- [x] Add `character_ids` field to subscription structure
  - [x] Update `add_subscription/2` to accept and store character_ids
  - [x] Default to empty list if not provided
  - [x] Validate character_ids are integers
- [x] Update `add_websocket_subscription/4` to accept character_ids parameter
- [x] Update subscription getter functions to include character_ids
- [x] Add character_ids to subscription state tracking

## Phase 2: Filtering Logic Implementation

### 2.1 Enhance Webhook Subscription Filtering
- [x] Update `send_webhook_notifications/3` in SubscriptionManager
- [x] Implement dual filtering logic (system OR character match)
  - [x] Keep existing system_id filtering
  - [x] Add character-based filtering using CharacterMatcher
  - [x] Ensure subscription matches if EITHER system OR character matches
- [x] Optimize for performance
  - [x] Pre-filter killmails that have no matching subscriptions
  - [x] Consider caching character extraction results

### 2.2 Create Subscription Filtering Helper
- [x] Create `lib/wanderer_kills/subscriptions/filter.ex`
- [x] Implement `matches_subscription?/2` function
  - [x] Check system_ids match (empty list means all systems)
  - [x] Check character_ids match (empty list means no character filtering)
  - [x] Return true if either matches
- [x] Add performance optimizations
  - [x] Convert lists to MapSets for O(1) lookups
  - [x] Cache parsed killmail character data

## Phase 3: WebSocket Channel Updates

### 3.1 Update Channel Join Logic
- [x] Modify `lib/wanderer_kills_web/channels/killmail_channel.ex`
- [x] Update join payload structure to accept `character_ids`
- [x] Validate character_ids format and type
- [x] Store character_ids in socket assigns
- [x] Update subscription registration with SubscriptionManager

### 3.2 Implement Channel Filtering
- [x] Create `should_send_killmail?/2` private function
- [x] Check both system and character matches
- [x] Use CharacterMatcher for character filtering
- [x] Update `handle_info({:killmail_update, killmail}, socket)` to use new filtering
- [x] Handle WebSocket subscription updates when character list changes

### 3.3 Channel Tests
- [x] Write tests for character-based filtering in channels
- [x] Test join with character_ids
- [x] Test killmail delivery with character matches
- [x] Test mixed system and character subscriptions

## Phase 4: API Endpoint Updates

### 4.1 Update Subscription Controller
- [x] Create `lib/wanderer_kills_web/controllers/subscription_controller.ex`
- [x] Update create action to accept character_ids
- [x] Update update action to allow character_ids modification
- [x] Add character_ids to subscription responses
- [x] Validate character_ids are valid integers

### 4.2 API Request Validation
- [x] Add character_ids validation in changeset/schema
- [x] Limit maximum number of character_ids per subscription (e.g., 1000)
- [x] Ensure character_ids are unique within a subscription
- [x] Add appropriate error messages for validation failures

### 4.3 API Documentation
- [x] Update API documentation for subscription endpoints
- [x] Add character_ids field to request/response examples
- [x] Document the OR logic between systems and characters
- [x] Add usage examples for character-based subscriptions

## Phase 5: Performance Optimization

### 5.1 Create Character Index
- [x] Design ETS table for character -> subscription mapping
- [x] Implement index maintenance on subscription add/remove
- [x] Add lookup functions for finding subscriptions by character
- [x] Write tests for index operations

### 5.2 Batch Processing Optimization
- [x] Implement batch character extraction from multiple killmails
- [x] Create efficient bulk matching algorithm
- [x] Add telemetry events for performance monitoring
- [x] Benchmark with realistic data volumes

### 5.3 Caching Strategy
- [x] Cache extracted character lists from killmails (5-minute TTL)
- [x] Add cache invalidation on subscription changes (not needed for character extraction cache)
- [x] Monitor cache hit rates

## Phase 6: Testing & Quality Assurance ✅ COMPLETED

### 6.1 Unit Tests
- [x] CharacterMatcher module tests (49 tests passing)
- [x] SubscriptionManager character filtering tests 
- [x] Filter module tests
- [x] API endpoint tests with character_ids

### 6.2 Integration Tests
- [x] End-to-end subscription with characters test (7 tests in integration_test.exs)
- [x] WebSocket subscription with character filtering
- [x] Mixed system and character subscription scenarios
- [x] Performance tests with large character lists

### 6.3 Load Testing
- [x] Test with 1000+ character_ids per subscription (✅ Under 100ms creation)
- [x] Test with 10,000+ concurrent subscriptions (✅ Under 10s indexing)
- [x] Measure filtering performance impact (✅ Under 1ms per killmail)
- [x] Identify and resolve bottlenecks (✅ All performance targets met)

**Performance Test Results:**
- 1000 character subscription creation: <100ms
- Character index lookups: <1ms for 10 operations
- Large killmail processing (500+ attackers): <10ms
- Batch processing 100 killmails: <1 second
- Concurrent operations (100 tasks): <10 seconds

## Phase 7: Monitoring & Observability ✅ COMPLETED

### 7.1 Add Telemetry Events
- [x] Character matching duration (CharacterMatcher.killmail_has_characters?)
- [x] Number of character matches per killmail (Filter.filter_killmails)
- [x] Subscription filtering performance (comprehensive telemetry in all modules)
- [x] Cache hit/miss rates (CharacterCache enhanced telemetry)
- [x] Character index operations (add/remove/update/lookup telemetry)

### 7.2 Update Health Checks
- [x] Add character subscription metrics to health checks (CharacterSubscriptionHealth module)
- [x] Monitor character index size and performance (ETS table stats, memory estimates)
- [x] Track subscription distribution (system vs character vs mixed ratios)
- [x] Integrated into main application health endpoint

### 7.3 Logging Enhancements
- [x] Add debug logging for character matching (via telemetry handlers)
- [x] Log subscription filter decisions (performance warnings for large operations)
- [x] Add performance warnings for large character lists (>100 characters, >50 killmails)
- [x] Cache effectiveness logging for batch operations (>50 killmails)
- [x] Character subscription activation logging (WebSocket subscriptions)

**Observability Features Added:**
- Comprehensive telemetry events for all character subscription operations
- Health checks accessible via `/health` endpoint with character subscription metrics
- Performance monitoring with automatic warnings for large operations
- Cache effectiveness tracking and reporting
- Debug-level telemetry logging for all operations

## Phase 8: Documentation & Deployment ✅ COMPLETED

### 8.1 Code Documentation
- [x] Document all new modules with @moduledoc (comprehensive documentation added to all modules)
- [x] Add @doc to all public functions (all public APIs documented with examples)
- [x] Include usage examples in documentation (examples in all module docs)
- [x] Document performance considerations (telemetry, benchmarks, optimization details)

### 8.2 Update Project Documentation
- [x] Update README with character subscription feature (added to features list and examples)
- [x] Add character subscription examples (JavaScript WebSocket examples with OR logic)
- [x] Document WebSocket protocol changes (comprehensive API guide updates)
- [x] Update API documentation (full WebSocket character subscription documentation)

### 8.3 Enhanced Documentation
- [x] Updated `/app/CHARACTER_SUBSCRIPTIONS.md` with comprehensive implementation details
- [x] Added performance benchmarks and monitoring information
- [x] Documented testing procedures and health check integration
- [x] Added troubleshooting and best practices guidance

**Documentation Coverage:**
- **Module Documentation**: All 6 core character subscription modules fully documented
- **API Documentation**: Complete WebSocket character subscription guide in API docs
- **Usage Examples**: JavaScript examples for all subscription patterns
- **Performance Guide**: Benchmarks, optimization tips, and monitoring setup
- **Integration Guide**: Step-by-step implementation and testing instructions

## Implementation Notes

### Data Structure Changes

**HTTP Webhook Subscription:**
```elixir
%{
  "id" => "sub_123",
  "subscriber_id" => "user_456",
  "system_ids" => [30000142, 30000143],
  "character_ids" => [95465499, 90379338],  # NEW
  "callback_url" => "https://example.com/webhook",
  "created_at" => ~U[2024-01-01 00:00:00Z]
}
```

**WebSocket Subscription:**
```elixir
%{
  id: "ws_sub_789",
  user_id: "user_456",
  systems: MapSet.new([30000142, 30000143]),
  characters: MapSet.new([95465499, 90379338]),  # NEW
  socket_pid: #PID<0.123.0>,
  connected_at: ~U[2024-01-01 00:00:00Z]
}
```

### API Examples

**Create Subscription with Characters:**
```http
POST /api/subscriptions
Content-Type: application/json

{
  "subscriber_id": "user123",
  "system_ids": [30000142],
  "character_ids": [95465499, 90379338],
  "callback_url": "https://example.com/webhook"
}
```

**WebSocket Join with Characters:**
```javascript
channel.join("killmail:subscription", {
  system_ids: [30000142],
  character_ids: [95465499, 90379338]
})
```

### Performance Targets
- Character filtering should add < 1ms latency per killmail
- Support up to 1000 character_ids per subscription
- Handle 10,000+ concurrent subscriptions
- Maintain current system throughput rates

### Backward Compatibility
- Existing subscriptions without character_ids continue to work
- Empty character_ids array means no character filtering
- API remains backward compatible
- WebSocket protocol extensions are optional