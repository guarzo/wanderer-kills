# WandererKills Integration Guide

## Overview

The WandererKills service provides real-time EVE Online killmail data through multiple integration patterns. This guide covers all available integration methods and provides practical examples for consuming the service.

## Quick Start

The service runs on `http://localhost:4004` by default and provides:

- **REST API** - Fetch kill data
- **WebSocket Channels** - Real-time kill notifications via Phoenix channels
- **Phoenix PubSub** - Direct message broadcasting for Elixir applications
- **Client Library** - Elixir behaviour for direct integration

## Authentication

Currently, the service does not require authentication.

## REST API Integration

### Base URL

```
http://localhost:4004/api/v1
```

### Kill Data Endpoints

#### Fetch System Kills

Get recent kills for a specific solar system.

```http
GET /api/v1/kills/system/{system_id}?since_hours={hours}&limit={limit}
```

**Parameters:**

- `system_id` (required) - EVE Online solar system ID
- `since_hours` (required) - Hours to look back for kills
- `limit` (optional) - Maximum kills to return (default: 100)

**Example Request:**

```bash
curl "http://localhost:4004/api/v1/kills/system/30000142?since_hours=24&limit=50"
```

**Example Response:**

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
          "alliance_id": 456789123,
          "alliance_name": "Victim Alliance",
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
            "weapon_type_id": 2456,
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

#### Bulk Fetch Multiple Systems

Get kills for multiple systems in a single request.

```http
POST /api/v1/kills/systems
Content-Type: application/json

{
  "system_ids": [30000142, 30000144, 30000145],
  "since_hours": 24,
  "limit": 50
}
```

**Example Response:**

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

#### Get Cached Kills

Retrieve cached kills without triggering a fresh fetch.

```http
GET /api/v1/kills/cached/{system_id}
```

#### Get Specific Killmail

Fetch details for a specific killmail.

```http
GET /api/v1/killmail/{killmail_id}
```

#### Get System Kill Count

Get the current kill count for a system.

```http
GET /api/v1/kills/count/{system_id}
```

**Example Response:**

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


## WebSocket Integration

Connect to the WebSocket endpoint for real-time kill notifications using Phoenix channels.

### Connection

```
ws://localhost:4004/socket
```

### Phoenix Socket Client Example (JavaScript)

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
  .receive('ok', resp => { 
    console.log('Joined successfully', resp);
  })
  .receive('error', resp => { 
    console.log('Unable to join', resp);
  });

// Listen for kill events
channel.on('new_kill', payload => {
  console.log('New kill:', payload.killmail_id);
  // Process the kill data
});

channel.on('system_stats', payload => {
  console.log(`System ${payload.system_id} has ${payload.kill_count} kills`);
});

// Subscribe to multiple systems
const systems = [30000142, 30000144];
channel.push('subscribe', { systems: systems })
  .receive('ok', resp => { 
    console.log('Subscribed to systems', resp);
  })
  .receive('error', resp => { 
    console.log('Failed to subscribe', resp);
  });

// Handle disconnections
socket.onError(() => console.log('Socket error'));
socket.onClose(() => console.log('Socket closed'));
```

### Channel Events

#### new_kill

Received when a new kill is detected:

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

Received when system statistics are updated:

```json
{
  "system_id": 30000142,
  "kill_count": 48,
  "timestamp": "2024-01-15T15:00:00Z"
}
```


## Real-time Integration (Elixir Applications)

For Elixir applications running in the same environment, you can subscribe directly to Phoenix PubSub topics.

### PubSub Topics

```elixir
# Subscribe to all kill updates
Phoenix.PubSub.subscribe(WandererKills.PubSub, "zkb:kills:updated")
Phoenix.PubSub.subscribe(WandererKills.PubSub, "zkb:detailed_kills:updated")

# Subscribe to specific system updates
Phoenix.PubSub.subscribe(WandererKills.PubSub, "zkb:system:#{system_id}")
Phoenix.PubSub.subscribe(WandererKills.PubSub, "zkb:system:#{system_id}:detailed")
```

### Message Handling

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

  def handle_info(%{type: :killmail_update, solar_system_id: system_id, kills: kills}, state) do
    IO.puts("Received #{length(kills)} new kills for system #{system_id}")
    # Process kills...
    {:noreply, state}
  end

  def handle_info(%{type: :killmail_count_update, solar_system_id: system_id, kills: count}, state) do
    IO.puts("System #{system_id} kill count updated to #{count}")
    # Update your local state...
    {:noreply, state}
  end
end
```

## Client Library Integration (Elixir)

For direct integration within Elixir applications, implement the `WandererKills.ClientBehaviour`.

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

### Implementing Your Own Client

```elixir
defmodule MyApp.KillsClient do
  @behaviour WandererKills.ClientBehaviour

  @impl true
  def get_system_killmails(system_id, since_hours, limit) do
    # Your implementation using the REST API
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

  # Implement other callbacks...
end
```

## Error Handling

The service returns standardized error responses:

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

### Common Error Types

- `invalid_parameter` - Invalid request parameters
- `not_found` - Resource not found
- `rate_limit_exceeded` - Rate limit exceeded
- `internal_error` - Server error
- `timeout` - Request timeout
- `external_api_error` - External API failure
- `validation_error` - Data validation failed

### Error Handling Best Practices

1. **Implement Retry Logic** - Use exponential backoff for transient errors
2. **Handle Rate Limits** - Respect 429 responses and retry-after headers
3. **Validate Parameters** - Check parameters client-side before requests
4. **Log Errors** - Include request context in error logs

## Rate Limiting

The service implements rate limiting to ensure fair usage:

- **Per-IP Limits**: 1000 requests per minute
- **Burst Limit**: 100 requests in 10 seconds
- **WebSocket Connections**: 10 concurrent connections per IP

### Rate Limit Headers

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 987
X-RateLimit-Reset: 1642258800
```

## Health and Monitoring

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

## Integration Examples

### Node.js Application

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

### Python Application

```python
import requests
import json

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

## Best Practices

### Performance

- **Batch Requests** - Use bulk endpoints for multiple systems
- **Cache Results** - Implement client-side caching with appropriate TTLs
- **Use Cached Endpoints** - Use `/cached/` endpoints for frequently accessed data
- **Limit Request Size** - Keep system lists under 50 systems per request
- **Use WebSocket** - For real-time updates instead of polling

### Reliability

- **Implement Circuit Breakers** - Fail fast when service is unavailable
- **Handle Duplicates** - Same kill may be delivered multiple times
- **Graceful Degradation** - Fallback to cached data when possible
- **Health Monitoring** - Regular health checks in production

### Security

- **Validate Webhooks** - Verify webhook authenticity in production
- **Rate Limiting** - Implement client-side rate limiting
- **HTTPS Only** - Use HTTPS in production environments
- **API Keys** - Implement proper authentication for production

## Field Normalization

The service normalizes field names for consistency:

- `solar_system_id` → `system_id`
- `killID` → `killmail_id`
- `killmail_time` → `kill_time`

All responses use the normalized field names internally.

## Troubleshooting

### Common Issues

1. **No Kills Returned**

   - Check if system ID is valid
   - Verify time range (some systems have no recent activity)
   - Check if service is properly fetching from zKillboard

2. **Webhook Not Receiving Data**

   - Verify callback URL is accessible from service
   - Check webhook endpoint returns 2xx status codes
   - Review logs for HTTP errors

3. **High Latency**

   - Use bulk endpoints for multiple systems
   - Implement client-side caching
   - Consider using cached endpoints

4. **Rate Limiting**
   - Implement exponential backoff
   - Reduce request frequency
   - Use WebSocket connections for real-time data

### Debug Information

Enable debug logging to troubleshoot issues:

```elixir
# In config/config.exs
config :logger, level: :debug

# View logs
docker logs wanderer-kills-container -f
```

## Monitoring Integration

The service provides comprehensive monitoring every 5 minutes in the logs:

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 WANDERER KILLS STATUS REPORT (5-minute summary)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌐 WEBSOCKET ACTIVITY:
   Active Connections: 15
   Active Subscriptions: 12 (covering 87 systems)

📤 KILL DELIVERY:
   Total Kills Sent: 1234 (Realtime: 1150, Preload: 84)
   Delivery Rate: 4.1 kills/minute

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

## Support

For issues and questions:

- **GitHub Issues**: [Create an issue](https://github.com/wanderer-industries/wanderer-kills/issues)
- **Documentation**: Check the `/docs` directory
- **Health Endpoint**: Monitor service status via `/health`

## API Versioning

The current API version is `v1`. Future versions will be released with backward compatibility guarantees:

- **URL Versioning**: `/api/v1/`
- **Deprecation Notice**: 6-month advance notice
- **Migration Guide**: Provided for breaking changes
