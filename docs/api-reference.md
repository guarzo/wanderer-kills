# WandererKills API Reference

## Base URL

```
http://localhost:4004/api/v1
```

## Authentication

No authentication required for current version.

## Endpoints

### Kill Data

| Method | Endpoint                    | Description                 |
| ------ | --------------------------- | --------------------------- |
| GET    | `/kills/system/{system_id}` | Get kills for a system      |
| POST   | `/kills/systems`            | Bulk fetch multiple systems |
| GET    | `/kills/cached/{system_id}` | Get cached kills only       |
| GET    | `/killmail/{killmail_id}`   | Get specific killmail       |
| GET    | `/kills/count/{system_id}`  | Get kill count for system   |

### WebSocket

| Endpoint   | Description                                    |
| ---------- | ---------------------------------------------- |
| `/socket`  | Phoenix WebSocket endpoint for real-time data  |
| `/websocket` | WebSocket connection information (REST)      |

### System

| Method | Endpoint  | Description    |
| ------ | --------- | -------------- |
| GET    | `/health` | Health check   |
| GET    | `/status` | Service status |

## Request Parameters

### GET /kills/system/{system_id}

- `since_hours` (required) - Hours to look back
- `limit` (optional) - Max kills to return (default: 100)

### POST /kills/systems

```json
{
  "system_ids": [30000142, 30000144],
  "since_hours": 24,
  "limit": 50
}
```


## Response Format

### Success Response

```json
{
  "data": { ... },
  "timestamp": "2024-01-15T15:00:00Z"
}
```

### Error Response

```json
{
  "error": {
    "type": "not_found",
    "message": "Resource not found",
    "code": "NOT_FOUND",
    "details": { ... }
  },
  "timestamp": "2024-01-15T15:00:00Z"
}
```

## Kill Object Structure

```json
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
```

## WebSocket Messages

### Connection

Connect to `/socket` endpoint using Phoenix Socket protocol. You'll need a Phoenix Socket client library.

### Channel Subscription

Join a channel for a specific system:
- Channel name: `killmails:system:{system_id}`
- Example: `killmails:system:30000142`

### Subscribe to Multiple Systems

After joining a channel, push a subscribe message:

```json
{
  "systems": [30000142, 30000144]
}
```

### Kill Update Event

Received as `new_kill` event on the channel:

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

### System Update Event

Received as `system_stats` event on the channel:

```json
{
  "system_id": 30000142,
  "kill_count": 48,
  "timestamp": "2024-01-15T15:00:00Z"
}
```

## HTTP Status Codes

| Code | Description    |
| ---- | -------------- |
| 200  | Success        |
| 400  | Bad Request    |
| 404  | Not Found      |
| 429  | Rate Limited   |
| 500  | Internal Error |

## Error Types

| Type                   | Description                      |
| ---------------------- | -------------------------------- |
| `invalid_parameter`    | Invalid request parameter        |
| `not_found`            | Resource not found               |
| `rate_limit_exceeded`  | Rate limit exceeded              |
| `internal_error`       | Server error                     |
| `timeout`              | Request timeout                  |
| `external_api_error`   | External API failure             |
| `validation_error`     | Data validation failed           |
| `missing_killmail_id`  | Killmail ID missing              |
| `invalid_format`       | Invalid data format              |
| `kill_too_old`         | Killmail outside time window     |


## PubSub Topics (Elixir Apps)

### Global Topics

- `zkb:kills:updated` - Kill count updates
- `zkb:detailed_kills:updated` - Detailed kill updates

### System-Specific Topics

- `zkb:system:#{system_id}` - All updates for system
- `zkb:system:#{system_id}:detailed` - Detailed kills for system

## Rate Limits

- **Per-IP**: 1000 requests/minute
- **Burst**: 100 requests/10 seconds
- **WebSocket**: 10 connections/IP
- **Subscription Limit**: 100 systems per subscription

## cURL Examples

### Get System Kills

```bash
curl "http://localhost:4004/api/v1/kills/system/30000142?since_hours=24&limit=50"
```

### Bulk Fetch

```bash
curl -X POST http://localhost:4004/api/v1/kills/systems \
  -H "Content-Type: application/json" \
  -d '{"system_ids":[30000142,30000144],"since_hours":24,"limit":50}'
```


### Health Check

```bash
curl http://localhost:4004/health
```

### WebSocket Connection (JavaScript)

```javascript
// Using Phoenix Socket library
import { Socket } from 'phoenix';

const socket = new Socket('ws://localhost:4004/socket');
socket.connect();

const channel = socket.channel('killmails:system:30000142');
channel.join()
  .receive('ok', resp => console.log('Joined successfully'))
  .receive('error', resp => console.log('Unable to join'));

// Listen for new kills
channel.on('new_kill', kill => console.log('New kill:', kill));
```

## Field Normalization

The API normalizes field names for consistency:

- `solar_system_id` → `system_id`
- `killID` → `killmail_id`
- `killmail_time` → `kill_time`

All timestamps are in ISO 8601 format (UTC).

## Cache Behavior

- Killmails are cached for 5 minutes
- System data is cached for 1 hour
- ESI enrichment data is cached for 24 hours
- Use `/kills/cached/` endpoints to retrieve only cached data

## Best Practices

1. **Use bulk endpoints** when fetching data for multiple systems
2. **Implement exponential backoff** for rate limit errors
3. **Subscribe to WebSocket** for real-time updates instead of polling
4. **Cache responses** client-side to reduce API calls
5. **Use structured error handling** based on error types
6. **Monitor health endpoint** for service availability
