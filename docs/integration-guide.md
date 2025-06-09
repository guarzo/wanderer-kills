# WandererKills Integration Guide

## Overview

The WandererKills service provides real-time EVE Online killmail data through multiple integration patterns. This guide covers all available integration methods and provides practical examples for consuming the service.

## Quick Start

The service runs on `http://localhost:4004` by default and provides:

- **REST API** - Fetch kill data and manage subscriptions
- **Real-time Updates** - Phoenix PubSub for internal applications
- **Webhooks** - HTTP callbacks for external services
- **Client Library** - Elixir behaviour for direct integration

## Authentication

Currently, the service does not require authentication for read operations. Subscription management endpoints may require API keys in production deployments.

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
        "solar_system_id": 30000142,
        "victim": {
          "character_id": 987654321,
          "corporation_id": 123456789,
          "alliance_id": 456789123,
          "ship_type_id": 671,
          "damage_taken": 2847
        },
        "attackers": [
          {
            "character_id": 111222333,
            "corporation_id": 444555666,
            "ship_type_id": 17918,
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
  "timestamp": "2024-01-15T15:00:00Z",
  "error": null
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
    "systems_kills": {
      "30000142": [...],
      "30000144": [...],
      "30000145": [...]
    }
  },
  "timestamp": "2024-01-15T15:00:00Z",
  "error": null
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
  }
}
```

### Subscription Management

#### Create Subscription

Subscribe to real-time updates for specific systems.

```http
POST /api/v1/subscriptions
Content-Type: application/json

{
  "subscriber_id": "my-service-v1",
  "system_ids": [30000142, 30000144],
  "callback_url": "https://my-service.com/webhooks/kills"
}
```

**Example Response:**

```json
{
  "data": {
    "subscription_id": "abc123def456",
    "status": "active"
  },
  "timestamp": "2024-01-15T15:00:00Z",
  "error": null
}
```

#### Remove Subscription

Cancel an existing subscription.

```http
DELETE /api/v1/subscriptions/{subscriber_id}
```

#### List Active Subscriptions

Get all active subscriptions.

```http
GET /api/v1/subscriptions
```

## Webhook Integration

When you create a subscription with a `callback_url`, the service will send HTTP POST requests to your endpoint when new kills are detected.

### Webhook Payload Formats

#### Kill Update Notification

```json
{
  "type": "detailed_kill_update",
  "data": {
    "solar_system_id": 30000142,
    "kills": [
      {
        "killmail_id": 123456789,
        "kill_time": "2024-01-15T14:30:00Z",
        "solar_system_id": 30000142,
        "victim": {...},
        "attackers": [...],
        "zkb": {...}
      }
    ],
    "timestamp": "2024-01-15T15:00:00Z"
  }
}
```

#### Kill Count Update

```json
{
  "type": "kill_count_update",
  "data": {
    "solar_system_id": 30000142,
    "count": 48,
    "timestamp": "2024-01-15T15:00:00Z"
  }
}
```

### Webhook Endpoint Requirements

Your webhook endpoint should:

- Accept HTTP POST requests
- Respond with 2xx status codes for successful processing
- Handle timeouts gracefully (10-second timeout)
- Implement idempotency (same kill may be sent multiple times)

**Example Webhook Handler (Python Flask):**

```python
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/webhooks/kills', methods=['POST'])
def handle_kill_webhook():
    data = request.get_json()

    if data['type'] == 'detailed_kill_update':
        for kill in data['data']['kills']:
            process_kill(kill)
    elif data['type'] == 'kill_count_update':
        update_system_count(
            data['data']['solar_system_id'],
            data['data']['count']
        )

    return jsonify({'status': 'received'}), 200

def process_kill(kill):
    # Your kill processing logic here
    print(f"New kill: {kill['killmail_id']} in system {kill['solar_system_id']}")

def update_system_count(system_id, count):
    # Your count update logic here
    print(f"System {system_id} now has {count} kills")
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

  def handle_info(%{type: :detailed_kill_update, solar_system_id: system_id, kills: kills}, state) do
    IO.puts("Received #{length(kills)} new kills for system #{system_id}")
    # Process kills...
    {:noreply, state}
  end

  def handle_info(%{type: :kill_count_update, solar_system_id: system_id, kills: count}, state) do
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
{:ok, kills} = Client.fetch_system_kills(30000142, 24, 100)

# Fetch multiple systems
{:ok, systems_kills} = Client.fetch_systems_kills([30000142, 30000144], 24, 50)

# Get cached data
cached_kills = Client.fetch_cached_kills(30000142)

# Manage subscriptions
{:ok, subscription_id} = Client.subscribe_to_kills(
  "my-app",
  [30000142],
  "https://my-app.com/webhooks"
)

:ok = Client.unsubscribe_from_kills("my-app")
```

### Implementing Your Own Client

```elixir
defmodule MyApp.KillsClient do
  @behaviour WandererKills.ClientBehaviour

  @impl true
  def fetch_system_kills(system_id, since_hours, limit) do
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
  "data": null,
  "error": "Invalid system ID",
  "code": "INVALID_PARAMETER",
  "details": {
    "parameter": "system_id",
    "value": "invalid"
  },
  "timestamp": "2024-01-15T15:00:00Z"
}
```

### Common Error Codes

- `INVALID_PARAMETER` - Invalid request parameters
- `NOT_FOUND` - Resource not found
- `RATE_LIMITED` - Rate limit exceeded
- `INTERNAL_ERROR` - Server error
- `TIMEOUT` - Request timeout

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
  "websocket_connected": true,
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

  async createSubscription(subscriberId, systemIds, callbackUrl) {
    const response = await axios.post(`${this.baseUrl}/subscriptions`, {
      subscriber_id: subscriberId,
      system_ids: systemIds,
      callback_url: callbackUrl,
    });
    return response.data.data;
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

    def create_subscription(self, subscriber_id, system_ids, callback_url=None):
        url = f"{self.base_url}/subscriptions"
        data = {
            'subscriber_id': subscriber_id,
            'system_ids': system_ids,
            'callback_url': callback_url
        }

        response = requests.post(url, json=data)
        response.raise_for_status()

        return response.json()['data']

# Usage
client = WandererKillsClient()
kills = client.get_system_kills(30000142, since_hours=24, limit=50)
print(f"Found {len(kills)} kills")

# Subscribe to updates
subscription = client.create_subscription(
    "my-python-app",
    [30000142, 30000144],
    "https://my-app.com/webhooks/kills"
)
print(f"Created subscription: {subscription['subscription_id']}")
```

## Best Practices

### Performance

- **Batch Requests** - Use bulk endpoints for multiple systems
- **Cache Results** - Implement client-side caching with appropriate TTLs
- **Use Cached Endpoints** - Use `/cached/` endpoints for frequently accessed data
- **Limit Request Size** - Keep system lists under 50 systems per request

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

## Support

For issues and questions:

- **GitHub Issues**: [Create an issue](https://github.com/wanderer-industries/wanderer-kills/issues)
- **Documentation**: Check the `/docs` directory
- **Health Endpoint**: Monitor service status via `/health`

## API Versioning

The current API version is `v1`. Future versions will be released with backward compatibility guarantees:

- **URL Versioning**: `/api/v1/` (WebSocket info available at `/websocket`)
- **Deprecation Notice**: 6 months advance notice
- **Migration Guide**: Provided for breaking changes
