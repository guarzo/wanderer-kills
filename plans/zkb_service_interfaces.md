# ZKB Service Interface Specification

## Overview

This document defines the interfaces that the new ZKB (zKillboard) service should provide to support killmail data fetching, caching, and real-time updates for the Wanderer application.

## Core Service Interfaces

### 1. HTTP REST API

#### Kill Data Endpoints

**Fetch System Kills**
```
GET /api/v1/kills/system/{system_id}
Query Parameters:
  - since_hours: integer (required) - Hours to look back for kills
  - limit: integer (optional) - Maximum number of kills to return

Response:
{
  "kills": [...],           // Array of kill objects
  "cached": boolean,        // Whether data came from cache
  "timestamp": "ISO8601",   // Response timestamp
  "error": null             // Error message if any
}
```

**Fetch Multiple Systems Kills**
```
POST /api/v1/kills/systems
Body:
{
  "system_ids": [integer],  // Array of system IDs
  "since_hours": integer,   // Hours to look back
  "limit": integer          // Optional limit per system
}

Response:
{
  "systems_kills": {
    "system_id": [...],     // Kill arrays keyed by system ID
    ...
  },
  "timestamp": "ISO8601",
  "error": null
}
```

**Get Cached Kills**
```
GET /api/v1/kills/cached/{system_id}

Response:
{
  "kills": [...],           // Cached kills for system
  "timestamp": "ISO8601",
  "error": null
}
```

**Get Specific Killmail**
```
GET /api/v1/killmail/{killmail_id}

Response:
{
  "killmail_id": integer,
  "kill_time": "ISO8601",
  "solar_system_id": integer,
  "victim": {...},
  "attackers": [...],
  "zkb": {...}
}
```

**Get System Kill Count**
```
GET /api/v1/kills/count/{system_id}

Response:
{
  "system_id": integer,
  "count": integer,         // Current kill count for system
  "timestamp": "ISO8601"
}
```

#### Subscription Management Endpoints

**Create Subscription**
```
POST /api/v1/subscriptions
Body:
{
  "subscriber_id": "string",    // Unique subscriber identifier
  "system_ids": [integer],      // Systems to subscribe to
  "callback_url": "string"      // Optional webhook URL
}

Response:
{
  "subscription_id": "string",
  "status": "active",
  "error": null
}
```

**Remove Subscription**
```
DELETE /api/v1/subscriptions/{subscriber_id}

Response:
{
  "status": "deleted",
  "error": null
}
```

**List Active Subscriptions**
```
GET /api/v1/subscriptions

Response:
{
  "subscriptions": [
    {
      "subscriber_id": "string",
      "system_ids": [integer],
      "created_at": "ISO8601"
    }
  ]
}
```

### 2. WebSocket Interface

**Connection**
```
WS /ws/kills

Messages:
{
  "type": "subscribe",
  "subscriber_id": "string",
  "system_ids": [integer]
}

{
  "type": "unsubscribe",
  "subscriber_id": "string"
}
```

**Real-time Updates**
```
{
  "type": "kill_update",
  "data": {
    "solar_system_id": integer,
    "kills": integer,
    "timestamp": "ISO8601"
  }
}

{
  "type": "detailed_kill_update",
  "data": {
    "solar_system_id": integer,
    "kills": [...],           // Full kill objects
    "timestamp": "ISO8601"
  }
}
```

### 3. Phoenix PubSub Topics

**Topic Structure**
```elixir
# Global kill updates
"zkb:kills:updated"                    # Basic kill count changes
"zkb:detailed_kills:updated"           # Detailed killmail updates

# System-specific updates
"zkb:system:#{system_id}"              # All updates for a system
"zkb:system:#{system_id}:detailed"     # Detailed kills for a system

# Subscriber-specific updates
"zkb:subscriber:#{subscriber_id}"      # Updates for specific subscriber
```

**Message Formats**
```elixir
# Kill count update
%{
  type: :kill_count_update,
  solar_system_id: integer(),
  kills: integer(),
  timestamp: DateTime.t()
}

# Detailed kill update
%{
  type: :detailed_kill_update,
  solar_system_id: integer(),
  kills: [kill_map()],
  timestamp: DateTime.t()
}

# Multiple systems update
%{
  type: :systems_kill_update,
  systems_kills: %{integer() => [kill_map()]},
  timestamp: DateTime.t()
}
```

## Data Structures

### Kill Object
```elixir
%{
  killmail_id: integer(),
  kill_time: DateTime.t(),
  solar_system_id: integer(),
  victim: %{
    character_id: integer() | nil,
    corporation_id: integer(),
    alliance_id: integer() | nil,
    ship_type_id: integer(),
    damage_taken: integer()
  },
  attackers: [
    %{
      character_id: integer() | nil,
      corporation_id: integer() | nil,
      alliance_id: integer() | nil,
      ship_type_id: integer() | nil,
      weapon_type_id: integer() | nil,
      damage_done: integer(),
      final_blow: boolean()
    }
  ],
  zkb: %{
    location_id: integer() | nil,
    hash: String.t(),
    fitted_value: float(),
    total_value: float(),
    points: integer(),
    npc: boolean(),
    solo: boolean(),
    awox: boolean()
  }
}
```

### Error Response
```elixir
%{
  error: String.t(),
  code: String.t(),           # "RATE_LIMITED", "NOT_FOUND", etc.
  details: map() | nil,       # Additional error context
  timestamp: DateTime.t()
}
```

## Client Behaviour Interface

The service should be consumable through a client that implements this behaviour:

```elixir
defmodule ZkbService.ClientBehaviour do
  @type kill :: map()
  @type system_id :: integer()
  @type subscriber_id :: String.t()

  # Direct fetch operations
  @callback fetch_system_kills(system_id(), integer()) :: 
    {:ok, [kill()]} | {:error, term()}
  
  @callback fetch_systems_kills([system_id()], integer()) :: 
    {:ok, %{system_id() => [kill()]}} | {:error, term()}
  
  @callback fetch_cached_kills(system_id()) :: [kill()]
  
  @callback fetch_cached_kills_for_systems([system_id()]) :: 
    %{system_id() => [kill()]}

  # Subscription management
  @callback subscribe_to_kills(subscriber_id(), [system_id()]) :: 
    :ok | {:error, term()}
  
  @callback unsubscribe_from_kills(subscriber_id()) :: :ok

  # Cache operations
  @callback get_killmail(integer()) :: kill() | nil
  @callback get_system_kill_count(system_id()) :: integer()
end
```

## Service Configuration

The service should accept configuration for:

```elixir
%{
  # HTTP server
  http_port: 4001,
  
  # PubSub configuration
  pubsub_adapter: Phoenix.PubSub.PG2,
  pubsub_name: ZkbService.PubSub,
  
  # Caching
  cache_ttl: :timer.hours(24),           # Killmail cache TTL
  system_kills_ttl: :timer.hours(1),     # System kill count TTL
  
  # Fetching behavior
  fetch_interval: :timer.seconds(15),     # Background fetch interval
  max_concurrent_fetches: 10,             # Concurrent fetch limit
  preload_cycle_ticks: 120,              # Full preload cycle
  
  # External services
  zkb_websocket_url: "wss://zkillboard.com/websocket/",
  esi_base_url: "https://esi.evetech.net",
  
  # Rate limiting
  max_requests_per_minute: 1000,
  burst_limit: 100
}
```

## Health and Monitoring Endpoints

```
GET /health
Response: {"status": "ok", "timestamp": "ISO8601"}

GET /metrics
Response: Prometheus-formatted metrics

GET /status
Response: {
  "cache_stats": {...},
  "active_subscriptions": integer,
  "websocket_connected": boolean,
  "last_kill_received": "ISO8601"
}
```

## Error Handling

The service should return appropriate HTTP status codes:

- `200` - Success
- `400` - Bad Request (invalid parameters)
- `404` - Not Found (system/killmail not found)
- `429` - Rate Limited
- `500` - Internal Server Error
- `503` - Service Unavailable

Error responses should include:
```json
{
  "error": "Human-readable error message",
  "code": "ERROR_CODE",
  "timestamp": "ISO8601",
  "details": {}
}
```

## Rate Limiting

The service should implement rate limiting:
- Per-IP limits for public endpoints
- Per-subscriber limits for authenticated endpoints
- Graceful degradation under load
- Proper retry-after headers

## Security Considerations

- API key authentication for subscription management
- Request validation and sanitization
- CORS configuration for web clients
- Rate limiting and DDoS protection
- Secure WebSocket connections (WSS in production) 