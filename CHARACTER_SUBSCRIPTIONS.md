# Character-Based Killmail Subscriptions

This document describes the character-based subscription feature added to WandererKills.

## Overview

The system now supports subscribing to killmails based on character IDs in addition to system IDs. WebSocket subscribers can receive real-time notifications when specific characters appear as either victims or attackers in killmails.

**Key Features:**
- **Real-time character tracking** - Instant notifications when tracked characters are involved in kills
- **Victim & attacker matching** - Characters are matched whether they appear as victims or attackers
- **OR logic filtering** - Killmails match if they satisfy either system OR character criteria
- **High performance** - Optimized for subscriptions with up to 1000 character IDs
- **Comprehensive observability** - Full telemetry, health checks, and monitoring

## Key Components

### 1. CharacterMatcher Module
- **Location**: `lib/wanderer_kills/killmails/character_matcher.ex`
- **Purpose**: Core logic for matching characters in killmails
- **Functions**:
  - `killmail_has_characters?/2` - Checks if a killmail contains any specified character IDs
  - `extract_character_ids/1` - Extracts all character IDs from a killmail

### 2. Filter Module
- **Location**: `lib/wanderer_kills/subscriptions/filter.ex`
- **Purpose**: Unified filtering logic for subscriptions
- **Functions**:
  - `matches_subscription?/2` - Checks if a killmail matches subscription criteria
  - `filter_killmails/2` - Filters a list of killmails based on subscription

### 3. CharacterIndex Module
- **Location**: `lib/wanderer_kills/subscriptions/character_index.ex`
- **Purpose**: High-performance ETS-based index for character → subscription lookups
- **Features**:
  - O(1) character lookups using ETS tables
  - Efficient batch operations for multiple characters
  - Automatic cleanup when subscriptions are removed
  - Memory usage monitoring and statistics

### 4. CharacterCache Module
- **Location**: `lib/wanderer_kills/killmails/character_cache.ex`
- **Purpose**: Caches character extraction results for performance
- **Features**:
  - 5-minute TTL for character extraction results
  - Batch processing with parallel cache lookups
  - Comprehensive telemetry and hit rate monitoring

### 5. BatchProcessor Module
- **Location**: `lib/wanderer_kills/killmails/batch_processor.ex`
- **Purpose**: Efficient bulk processing of killmails and subscriptions
- **Features**:
  - Parallel character extraction and matching
  - Subscription grouping for efficient delivery
  - Performance optimized for large-scale operations

### 6. SubscriptionManager Updates
- **Location**: `lib/wanderer_kills/subscription_manager.ex`
- **Changes**:
  - Added `character_ids` field to subscription data structure
  - Integration with CharacterIndex for efficient character tracking
  - Updated statistics to include character subscription metrics

### 7. WebSocket Channel Updates
- **Location**: `lib/wanderer_kills_web/channels/killmail_channel.ex`
- **Changes**:
  - Accept `character_ids` array in join parameters
  - Added `subscribe_characters` and `unsubscribe_characters` handlers
  - Enhanced killmail filtering using unified Filter module

### 8. Observability & Monitoring
- **CharacterSubscriptionHealth**: Health checks for all character subscription components
- **Telemetry Events**: Comprehensive performance monitoring for all operations
- **Performance Logging**: Automatic warnings for large operations and slow performance

## Usage Examples

### WebSocket Character Subscription

#### Basic Character Subscription
```javascript
import { Socket } from 'phoenix';

// Connect to WebSocket
const socket = new Socket('ws://localhost:4004/socket', {
  params: { client_identifier: 'my_client' }
});
socket.connect();

// Join channel and subscribe to characters
const channel = socket.channel('killmails:subscription', {});
channel.join()
  .receive('ok', resp => console.log('Joined successfully', resp))
  .receive('error', resp => console.log('Failed to join', resp));

// Subscribe to specific characters
channel.push('subscribe_characters', { 
  character_ids: [95465499, 90379338] 
})
  .receive('ok', resp => console.log('Subscribed to characters:', resp))
  .receive('error', resp => console.log('Failed to subscribe:', resp));

// Listen for killmails
channel.on('new_kill', payload => {
  console.log('Character involved in kill:', payload);
});
```

#### Mixed System and Character Subscription
```javascript
// Subscribe to both systems and characters using OR logic
channel.push('subscribe', { 
  systems: [30000142, 30000144],      // Jita and Amarr systems
  character_ids: [95465499, 90379338]  // Specific characters
})
  .receive('ok', resp => console.log('Mixed subscription active:', resp));

// This will receive killmails where:
// - Kill occurred in Jita (30000142) OR Amarr (30000144) OR
// - Character 95465499 appears as victim or attacker OR  
// - Character 90379338 appears as victim or attacker
```

#### Managing Character Subscriptions
```javascript
// Add more characters to existing subscription
channel.push('subscribe_characters', { 
  character_ids: [12345678, 87654321] 
});

// Remove specific characters from subscription
channel.push('unsubscribe_characters', { 
  character_ids: [95465499] 
});

// Unsubscribe from all characters
channel.push('unsubscribe_characters', { character_ids: [] });
```

## Filtering Logic

Subscriptions use **OR** logic between systems and characters:
- A killmail matches if it's in a subscribed system **OR** contains a subscribed character
- Character matching checks both victims and all attackers
- Empty character_ids means no character filtering (system-only)
- Empty system_ids means no system filtering (character-only)

## Performance Characteristics

### Architecture Optimizations
- **ETS-based indexing** - O(1) character lookups using CharacterIndex module
- **Character caching** - 5-minute TTL caching of character extraction results
- **Parallel processing** - Batch operations use `Task.async_stream` for concurrency
- **MapSet usage** - O(1) membership checks during character matching
- **Memory efficiency** - Optimized data structures for large character lists

### Performance Benchmarks
- **Character matching**: <1ms for 1000 character subscription
- **Index operations**: <5ms for batch lookups of 100 characters  
- **Cache effectiveness**: >90% hit rate for repeated killmail processing
- **Concurrent processing**: 100 subscriptions processed in <10 seconds
- **Large killmail handling**: 500+ attackers processed in <10ms

### Monitoring & Alerting
- **Telemetry events** for all major operations with timing metrics
- **Performance logging** for operations >100ms duration
- **Health checks** monitoring index size and cache effectiveness
- **Memory usage tracking** with automatic warnings for large indexes

## Limits & Recommendations

### System Limits
- **Maximum character IDs per subscription**: 1000
- **Recommended character IDs per subscription**: 100-500 for optimal performance
- **Character index memory**: Monitored with warnings at 1M+ entries
- **Cache TTL**: 5 minutes (configurable via `:character_cache, :ttl_ms`)

### Performance Recommendations
- Use character subscriptions for <100 characters when possible
- Combine system and character filtering to reduce load
- Monitor health checks for index performance metrics
- Use batch operations for processing multiple killmails

## Testing & Validation

### Test Coverage
The implementation includes comprehensive test coverage:
- **Unit tests**: CharacterMatcher, Filter, CharacterIndex, CharacterCache modules
- **Integration tests**: End-to-end subscription workflows
- **Performance tests**: Large-scale character lists and concurrent operations
- **Load tests**: Concurrent subscription creation/removal scenarios

### Running Tests
```bash
# All character subscription tests
MIX_ENV=test mix test test/integration/character_subscription_integration_test.exs \
  test/wanderer_kills/killmails/character_matcher_test.exs \
  test/wanderer_kills/subscriptions/filter_test.exs \
  test/wanderer_kills/subscriptions/character_index_test.exs

# Performance and load tests
MIX_ENV=test mix test test/performance/character_subscription_performance_test.exs \
  --include performance --include load_test

# All related tests (49 unit tests + 7 integration tests + 7 performance tests)
MIX_ENV=test mix test | grep -E "(character|subscription)" 
```

## Health Monitoring

### Health Check Endpoint
Character subscription health is included in the application health check:
```bash
curl http://localhost:4004/health
```

### Health Metrics
- **Subscription Manager**: Process status and subscription counts
- **Character Index**: ETS table size, memory usage, operation performance  
- **Character Cache**: Cache responsiveness and hit rate statistics
- **Overall Health**: Component integration and system performance

### Telemetry Integration
All character subscription operations emit telemetry events for monitoring:
- Character matching duration and results
- Filtering performance with batch sizes
- Index operation timings (add/remove/lookup)
- Cache hit/miss rates with key metadata