# Smart Rate Limiting Implementation Plan

## Overview

Replace simple retry-based rate limiting with an intelligent system that handles high-volume WebSocket subscriptions efficiently while respecting zKillboard's API limits.

## Current Problem

When clients subscribe to many systems (50+), the preloader hits rate limits:
- zKillboard capacity: 100 requests
- Multiple clients × 50 systems = rapid rate limit exhaustion
- Failed requests are simply logged as errors
- No intelligent retry or queue management

## Solution Architecture

### Phase 1: Core Smart Rate Limiter ✅ IMPLEMENTED
**File**: `/lib/wanderer_kills/ingest/smart_rate_limiter.ex`

**Features**:
- Priority-based request queuing (realtime > preload > background > bulk)
- Token bucket rate limiting with configurable refill
- Circuit breaker pattern for persistent failures
- Request timeout handling
- Adaptive rate window detection

**Priority Levels**:
1. **Realtime** (1) - Live killmail fetches for active subscriptions
2. **Preload** (2) - WebSocket client preload requests  
3. **Background** (3) - System updates and maintenance
4. **Bulk** (4) - Large batch operations

### Phase 2: Request Coalescing ✅ IMPLEMENTED
**File**: `/lib/wanderer_kills/ingest/request_coalescer.ex`

**Features**:
- Deduplicates identical API requests
- Shares results among multiple requesters
- Reduces API calls when multiple clients want same data
- Automatic timeout handling for stalled requests

**Example**: 5 clients subscribe to Jita (system 30000142) simultaneously
- **Before**: 5 separate API calls to zKillboard
- **After**: 1 API call, result shared with all 5 clients

### Phase 3: Integration Points ✅ IN PROGRESS

#### 3.1 Update Preloader to Use Smart Rate Limiter ✅ IMPLEMENTED
**File**: `/lib/wanderer_kills/subs/preloader.ex`

**Changes Made**:
- Added `fetch_system_kills_smart/3` function with feature flag support
- Integrated RequestCoalescer for duplicate request elimination  
- Added fallback to direct ZkbClient when feature flags disabled
- Updated ZkbClient call to use smart rate limiting

**Feature Flags Added**:
- `:smart_rate_limiting` - Controls SmartRateLimiter usage
- `:request_coalescing` - Controls RequestCoalescer usage

**Configuration Added**:
- Smart rate limiter token bucket settings
- Request coalescer timeout settings  
- Services added to application supervisor conditionally

#### 3.2 Update WebSocket Channel Preload ✅ IMPLEMENTED
**File**: `/lib/wanderer_kills_web/channels/killmail_channel.ex`

**Changes Made**:
- Added feature flag check for request coalescing
- Integrated RequestCoalescer for WebSocket preloads  
- Maintained fallback to direct Preloader calls
- Uses coalescing key `{:websocket_preload, system_id, limit, 24}` to avoid duplicate preloads

**Benefits**:
- Multiple clients subscribing to same system share preload results
- Reduces API calls during high-traffic periods
- Maintains compatibility when feature flags disabled

#### 3.3 Update ZkbClient for Rate Limit Detection ⏳ TODO
**File**: `/lib/wanderer_kills/ingest/killmails/zkb_client.ex`

```elixir
# TODO: Detect rate limit responses and feed back to SmartRateLimiter
defp handle_rate_limit_response(response) do
  case response do
    {:error, %{type: :rate_limited, details: %{retry_after_ms: retry_after}}} ->
      # Notify SmartRateLimiter of detected rate limit window
      SmartRateLimiter.update_rate_window(retry_after)
    _ -> :ok
  end
end
```

### Phase 4: Monitoring & Observability ✅ IMPLEMENTED

#### 4.1 Add Smart Rate Limiter Metrics ✅ IMPLEMENTED
**File**: `/lib/wanderer_kills/core/observability/monitoring.ex`

**Changes Made**:
- Added `collect_rate_limiter_metrics/0` function
- Integrated rate limiter metrics into comprehensive metrics collection
- Handles both enabled and disabled feature states
- Collects stats from both SmartRateLimiter and RequestCoalescer

**Metrics Collected**:
- Queue sizes and pending request counts
- Current token levels and circuit breaker states
- Feature flag status and component health
- Error states when components unreachable

#### 4.2 Health Check Integration ✅ IMPLEMENTED
**File**: `/lib/wanderer_kills/core/observability/health_checks.ex`

**Changes Made**:
- Added `check_rate_limiter_health/1` function
- Checks circuit breaker state and queue sizes
- Validates component availability and responsiveness
- Provides detailed health status for each component

**Health Checks**:
- Circuit breaker state (fails if `:open`)
- Queue size thresholds (warns if >1000 queued requests)
- Component availability (SmartRateLimiter and RequestCoalescer)
- Feature flag status and configuration

## Configuration

### New Configuration Options

```elixir
# config/config.exs
config :wanderer_kills, :smart_rate_limiter,
  # Token bucket configuration
  max_tokens: 150,              # Increased from 100
  refill_rate: 75,              # Tokens per second
  refill_interval_ms: 1000,     # How often to refill

  # Circuit breaker
  circuit_failure_threshold: 10,  # Failures before opening circuit
  circuit_timeout_ms: 60_000,     # How long circuit stays open

  # Queue management  
  max_queue_size: 5000,           # Max queued requests
  queue_timeout_ms: 300_000,      # 5 minutes max queue time

  # Request coalescing
  coalesce_timeout_ms: 30_000     # Max time to wait for coalesced request
```

## Migration Strategy

### Step 1: Add Services to Application Supervisor
```elixir
# lib/wanderer_kills/application.ex
children = [
  # ... existing children ...
  {WandererKills.Ingest.SmartRateLimiter, smart_rate_limiter_config()},
  {WandererKills.Ingest.RequestCoalescer, request_coalescer_config()},
]
```

### Step 2: Feature Flag Rollout
```elixir
# Enable gradually with feature flag
config :wanderer_kills, :features,
  smart_rate_limiting: true,     # Start with false, enable after testing
  request_coalescing: true
```

### Step 3: Update Call Sites
1. **Preloader** - Replace direct ZkbClient calls
2. **WebSocket Channel** - Use coalescing for preloads  
3. **Background Jobs** - Use bulk priority for maintenance tasks

### Step 4: Monitor and Tune
1. Watch queue sizes and circuit breaker state
2. Adjust token bucket parameters based on observed patterns
3. Monitor coalescing effectiveness (requests saved)

## Expected Benefits

### Performance Improvements
- **90% reduction** in duplicate API calls during high-traffic periods
- **Graceful degradation** under rate limits instead of failures
- **Prioritized processing** ensures real-time requests get precedence

### Operational Benefits  
- **Automatic rate limit recovery** without manual intervention
- **Detailed observability** into rate limiting behavior
- **Configurable limits** that can be tuned without code changes

### Scalability Benefits
- **Support for 1000+ concurrent WebSocket clients**
- **Efficient resource utilization** through request sharing
- **Predictable performance** under load

## Testing Strategy

### Unit Tests
- SmartRateLimiter token bucket behavior
- RequestCoalescer deduplication logic
- Circuit breaker state transitions

### Integration Tests  
- End-to-end WebSocket subscription with rate limiting
- Multiple client scenarios with coalescing
- Rate limit recovery testing

### Load Tests
- 100+ concurrent WebSocket connections
- Burst traffic scenarios
- Circuit breaker activation/recovery

## Rollback Plan

If issues arise:
1. **Disable feature flags** to revert to direct ZkbClient calls
2. **Increase basic rate limits** as temporary measure
3. **Monitor logs** for any stuck requests or memory leaks
4. **Gradual re-enablement** after fixes

## Implementation Timeline

- **Week 1**: Phase 3 integration + configuration
- **Week 2**: Testing and monitoring setup  
- **Week 3**: Gradual feature flag rollout
- **Week 4**: Full deployment and tuning

## Success Metrics

- ✅ **Zero rate limit errors** during normal operation
- ✅ **Sub-second response times** for preload requests
- ✅ **>95% request coalescing efficiency** during peak traffic
- ✅ **Circuit breaker activations < 1/day** in steady state