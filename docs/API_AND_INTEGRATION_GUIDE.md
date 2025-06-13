# WandererKills API & Integration Guide

## Overview

WandererKills is a real-time EVE Online killmail data service that provides multiple integration patterns for consuming killmail data. The service fetches data from zKillboard's RedisQ stream and enriches it with ESI (EVE Swagger Interface) data.

**Service Information:**
- **Default Port**: 4004
- **Base URL**: `http://localhost:4004/api/v1`
- **API Version**: v1
- **Authentication**: None required (current version)

**Integration Options:**
- **REST API** - HTTP endpoints for fetching killmail data
- **WebSocket** - Real-time kill notifications via Phoenix channels  
- **PubSub** - Direct message broadcasting for Elixir applications
- **Client Library** - Elixir behaviour for type-safe integration

---

## REST API Integration

### Base URL
```
http://localhost:4004/api/v1
```

### Core Endpoints

| Method | Endpoint                    | Description                 |
| ------ | --------------------------- | --------------------------- |
| GET    | `/kills/system/{system_id}` | Get kills for a system      |
| POST   | `/kills/systems`            | Bulk fetch multiple systems |
| GET    | `/kills/cached/{system_id}` | Get cached kills only       |
| GET    | `/killmail/{killmail_id}`   | Get specific killmail       |
| GET    | `/kills/count/{system_id}`  | Get kill count for system   |
| GET    | `/health`                   | Health check                |
| GET    | `/status`                   | Service status              |

### System Kills

#### Single System
```http
GET /api/v1/kills/system/{system_id}?since_hours={hours}&limit={limit}
```

**Parameters:**
- `system_id` (required) - EVE Online solar system ID
- `since_hours` (required) - Hours to look back for kills
- `limit` (optional) - Maximum kills to return (default: 100)

**Example:**
```bash
curl "http://localhost:4004/api/v1/kills/system/30000142?since_hours=24&limit=50"
```

**Response:**
```json
{
  "data": {
    "kills": [
      {
        "killmail_id": 123456789,
        "kill_time": "2024-01-15T14:30:00Z",
        "system_id": 30000142,
        "victim": {
          "character_id": 987654321,
          "character_name": "Victim Name",
          "corporation_id": 123456789,
          "corporation_name": "Victim Corp",
          "ship_type_id": 671,
          "ship_name": "Raven",
          "damage_taken": 2847
        },
        "attackers": [
          {
            "character_id": 111222333,
            "character_name": "Attacker Name", 
            "corporation_id": 444555666,
            "corporation_name": "Attacker Corp",
            "ship_type_id": 17918,
            "ship_name": "Rattlesnake",
            "damage_done": 2847,
            "final_blow": true
          }
        ],
        "zkb": {
          "location_id": 50000001,
          "hash": "abc123def456",
          "fitted_value": 150000000.0,
          "total_value": 152000000.0,
          "points": 15,
          "npc": false,
          "solo": true,
          "awox": false
        }
      }
    ],
    "cached": false
  },
  "timestamp": "2024-01-15T15:00:00Z"
}
```

#### Multiple Systems (Bulk)
```http
POST /api/v1/kills/systems
Content-Type: application/json

{
  "system_ids": [30000142, 30000144, 30000145],
  "since_hours": 24,
  "limit": 50
}
```

**Response:**
```json
{
  "data": {
    "systems_killmails": {
      "30000142": [...],
      "30000144": [...],
      "30000145": [...]
    }
  },
  "timestamp": "2024-01-15T15:00:00Z"
}
```

### Cached Data
```http
GET /api/v1/kills/cached/{system_id}
```
Returns only cached kills without triggering a fresh fetch.

### Specific Killmail
```http
GET /api/v1/killmail/{killmail_id}
```

### Kill Count
```http
GET /api/v1/kills/count/{system_id}
```

**Response:**
```json
{
  "data": {
    "system_id": 30000142,
    "count": 47,
    "timestamp": "2024-01-15T15:00:00Z"
  },
  "timestamp": "2024-01-15T15:00:00Z"
}
```

---

## WebSocket Integration

### Connection
Connect to the WebSocket endpoint using Phoenix Socket protocol:
```
ws://localhost:4004/socket
```

### JavaScript Example
```javascript
import { Socket } from 'phoenix';

// Connect to the socket
const socket = new Socket('ws://localhost:4004/socket', {
  params: { client_identifier: 'my-app' }
});

socket.connect();

// Join a killmail channel for a specific system
const channel = socket.channel('killmails:system:30000142', {});

channel.join()
  .receive('ok', resp => console.log('Joined successfully', resp))
  .receive('error', resp => console.log('Unable to join', resp));

// Listen for kill events
channel.on('new_kill', payload => {
  console.log('New kill:', payload.killmail_id);
});

channel.on('system_stats', payload => {
  console.log(`System ${payload.system_id} has ${payload.kill_count} kills`);
});

// Subscribe to multiple systems
channel.push('subscribe', { systems: [30000142, 30000144] })
  .receive('ok', resp => console.log('Subscribed to systems', resp))
  .receive('error', resp => console.log('Failed to subscribe', resp));
```

### Character-Based Subscriptions

WandererKills supports character-based subscriptions, allowing you to track specific players as victims or attackers across all systems.

#### Character Subscription Methods

```javascript
// Subscribe to specific characters
channel.push('subscribe_characters', { character_ids: [95465499, 90379338] })
  .receive('ok', resp => console.log('Subscribed to characters', resp))
  .receive('error', resp => console.log('Failed to subscribe to characters', resp));

// Mixed subscription (systems OR characters)
channel.push('subscribe', { 
  systems: [30000142], 
  character_ids: [95465499, 90379338] 
})
  .receive('ok', resp => console.log('Mixed subscription active', resp));

// Unsubscribe from specific characters
channel.push('unsubscribe_characters', { character_ids: [95465499] })
  .receive('ok', resp => console.log('Unsubscribed from characters', resp));
```

#### Character Subscription Features

- **OR Logic**: Killmails are delivered if they match **either** system IDs **or** character IDs
- **Victim & Attacker Matching**: Characters are matched whether they appear as victims or attackers  
- **Performance Optimized**: Efficient character indexing for fast lookups with large character lists
- **Scale Support**: Up to 1000 character IDs per subscription
- **Real-time Processing**: Sub-millisecond character matching performance

#### Character Subscription Parameters

| Parameter | Type | Description | Required |
|-----------|------|-------------|----------|
| `character_ids` | integer[] | EVE Online character IDs to track | Yes |

**Example Character IDs:**
- `95465499` - Example character ID
- `90379338` - Another character ID

#### Filtering Logic

```javascript
// This subscription will receive killmails where:
// - The killmail occurred in system 30000142 (Jita), OR
// - Character 95465499 appears as victim or attacker, OR  
// - Character 90379338 appears as victim or attacker
channel.push('subscribe', { 
  systems: [30000142], 
  character_ids: [95465499, 90379338] 
});
```

### Channel Events

#### new_kill
```json
{
  "killmail_id": 123456789,
  "kill_time": "2024-01-15T14:30:00Z", 
  "system_id": 30000142,
  "victim": {...},
  "attackers": [...],
  "zkb": {...}
}
```

#### system_stats
```json
{
  "system_id": 30000142,
  "kill_count": 48,
  "timestamp": "2024-01-15T15:00:00Z"
}
```

---

## PubSub Integration (Elixir Applications)

For Elixir applications running in the same environment, subscribe directly to Phoenix PubSub topics:

### Topic Structure
- `zkb:system:{system_id}` - All updates for system
- `zkb:system:{system_id}:detailed` - Detailed kills for system
- `zkb:all_systems` - Global kill updates

### Example Implementation
```elixir
defmodule MyApp.KillSubscriber do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    # Subscribe to Jita system kills
    Phoenix.PubSub.subscribe(WandererKills.PubSub, "zkb:system:30000142")
    {:ok, state}
  end

  def handle_info(%{type: :killmail_update, system_id: system_id, kills: kills}, state) do
    IO.puts("Received #{length(kills)} new kills for system #{system_id}")
    {:noreply, state}
  end

  def handle_info(%{type: :killmail_count_update, system_id: system_id, count: count}, state) do
    IO.puts("System #{system_id} kill count updated to #{count}")
    {:noreply, state}
  end
end
```

---

## Client Library Integration (Elixir)

### Using the Built-in Client
```elixir
# Add to your application's dependencies
{:wanderer_kills, path: "../wanderer_kills"}

# Use the client directly
alias WandererKills.Client

# Fetch system kills
{:ok, kills} = Client.get_system_killmails(30000142, 24, 100)

# Fetch multiple systems
{:ok, systems_kills} = Client.get_systems_killmails([30000142, 30000144], 24, 50)

# Get cached data
cached_kills = Client.get_cached_killmails(30000142)
```

### Custom Client Implementation
```elixir
defmodule MyApp.KillsClient do
  @behaviour WandererKills.ClientBehaviour

  @impl true
  def get_system_killmails(system_id, since_hours, limit) do
    url = "http://wanderer-kills:4004/api/v1/kills/system/#{system_id}"
    params = %{since_hours: since_hours, limit: limit}

    case HTTPoison.get(url, [], params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        %{"data" => %{"kills" => kills}} = Jason.decode!(body)
        {:ok, kills}
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

---

## Error Handling

### Standard Error Response
```json
{
  "error": {
    "type": "not_found",
    "message": "Resource not found",
    "code": "NOT_FOUND",
    "details": {
      "resource": "killmail",
      "id": 123456789
    }
  },
  "timestamp": "2024-01-15T15:00:00Z"
}
```

### Error Types
| Type                   | Description                      |
| ---------------------- | -------------------------------- |
| `invalid_parameter`    | Invalid request parameter        |
| `not_found`            | Resource not found               |
| `rate_limit_exceeded`  | Rate limit exceeded              |
| `internal_error`       | Server error                     |
| `timeout`              | Request timeout                  |
| `external_api_error`   | External API failure             |
| `validation_error`     | Data validation failed           |

### HTTP Status Codes
| Code | Description    |
| ---- | -------------- |
| 200  | Success        |
| 400  | Bad Request    |
| 404  | Not Found      |
| 429  | Rate Limited   |
| 500  | Internal Error |

---

## Rate Limiting

### Limits
- **Per-IP**: 1000 requests/minute
- **Burst**: 100 requests/10 seconds
- **WebSocket**: 10 connections/IP
- **Subscription Limit**: 100 systems per subscription

### Headers
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 987
X-RateLimit-Reset: 1642258800
```

---

## Health & Monitoring

### Health Check
```http
GET /health
```

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-01-15T15:00:00Z"
}
```

### Service Status
```http
GET /status
```

**Response:**
```json
{
  "cache_stats": {
    "hit_rate": 0.85,
    "size": 15420
  },
  "active_subscriptions": 42,
  "websocket_connections": 15,
  "last_kill_received": "2024-01-15T14:58:30Z"
}
```

---

## Integration Examples

### Node.js
```javascript
const axios = require("axios");

class WandererKillsClient {
  constructor(baseUrl = "http://localhost:4004/api/v1") {
    this.baseUrl = baseUrl;
  }

  async getSystemKills(systemId, sinceHours = 24, limit = 100) {
    try {
      const response = await axios.get(
        `${this.baseUrl}/kills/system/${systemId}`,
        { params: { since_hours: sinceHours, limit } }
      );
      return response.data.data.kills;
    } catch (error) {
      console.error("Failed to fetch kills:", error.response?.data);
      throw error;
    }
  }
}

// Usage
const client = new WandererKillsClient();
const kills = await client.getSystemKills(30000142, 24, 50);
console.log(`Found ${kills.length} kills`);
```

### Python
```python
import requests

class WandererKillsClient:
    def __init__(self, base_url='http://localhost:4004/api/v1'):
        self.base_url = base_url

    def get_system_kills(self, system_id, since_hours=24, limit=100):
        url = f"{self.base_url}/kills/system/{system_id}"
        params = {'since_hours': since_hours, 'limit': limit}

        response = requests.get(url, params=params)
        response.raise_for_status()

        return response.json()['data']['kills']

# Usage
client = WandererKillsClient()
kills = client.get_system_kills(30000142, since_hours=24, limit=50)
print(f"Found {len(kills)} kills")
```

---

## Data Formats & Field Normalization

### Field Mapping
The API normalizes field names for consistency:
- `solar_system_id` → `system_id`
- `killID` → `killmail_id`
- `killmail_time` → `kill_time`

### Timestamps
All timestamps are in ISO 8601 format (UTC).

### Cache Behavior
- **Killmails**: Cached for 5 minutes
- **System data**: Cached for 1 hour  
- **ESI enrichment**: Cached for 24 hours

---

## Best Practices

### Performance
- **Use bulk endpoints** for multiple systems
- **Implement client-side caching** with appropriate TTLs
- **Use cached endpoints** for frequently accessed data
- **Subscribe to WebSocket** for real-time updates instead of polling

### Reliability
- **Implement circuit breakers** for service failures
- **Handle duplicates** - same kill may be delivered multiple times
- **Graceful degradation** - fallback to cached data when possible
- **Regular health monitoring** in production

### Error Handling
- **Implement retry logic** with exponential backoff
- **Respect rate limits** - handle 429 responses
- **Validate parameters** client-side before requests
- **Log errors** with request context

---

## Troubleshooting

### Common Issues

1. **No Kills Returned**
   - Check system ID validity
   - Verify time range (some systems have no recent activity)
   - Ensure service is fetching from zKillboard

2. **High Latency**
   - Use bulk endpoints for multiple systems
   - Implement client-side caching
   - Consider cached endpoints

3. **Rate Limiting**
   - Implement exponential backoff
   - Reduce request frequency
   - Use WebSocket for real-time data

### Debug Information
Enable debug logging:
```elixir
# In config/config.exs
config :logger, level: :debug
```

---

## Monitoring Integration

The service provides comprehensive 5-minute status reports:

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 WANDERER KILLS STATUS REPORT (5-minute summary)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌐 WEBSOCKET ACTIVITY:
   Active Connections: 15
   Active Subscriptions: 12 (covering 87 systems)

📤 KILL DELIVERY:
   Total Kills Sent: 1234 (Realtime: 1150, Preload: 84)

🔄 REDISQ ACTIVITY:
   Kills Processed: 327
   Active Systems: 45

💾 CACHE PERFORMANCE:
   Hit Rate: 87.5%
   Cache Size: 2156 entries

📦 STORAGE METRICS:
   Total Killmails: 15234
   Unique Systems: 234
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Support & Resources

- **GitHub Issues**: Report bugs or request features
- **Health Endpoint**: Monitor service status
- **API Versioning**: 6-month deprecation notice for breaking changes
- **Migration Guide**: Provided for major version changes

---

## External Dependencies

The service integrates with:
- **zKillboard RedisQ** - Real-time killmail stream
- **EVE ESI API** - Killmail details and validation

Rate limiting and caching ensure reliable operation while respecting external service limits.
