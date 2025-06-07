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

### Subscriptions

| Method | Endpoint                         | Description         |
| ------ | -------------------------------- | ------------------- |
| POST   | `/subscriptions`                 | Create subscription |
| DELETE | `/subscriptions/{subscriber_id}` | Remove subscription |
| GET    | `/subscriptions`                 | List subscriptions  |

### System

| Method | Endpoint  | Description    |
| ------ | --------- | -------------- |
| GET    | `/health` | Health check   |
| GET    | `/status` | Service status |

## Request Parameters

### GET /kills/system/{system_id}

- `since_hours` (required) - Hours to look back
- `limit` (optional) - Max kills to return

### POST /kills/systems

```json
{
  "system_ids": [30000142, 30000144],
  "since_hours": 24,
  "limit": 50
}
```

### POST /subscriptions

```json
{
  "subscriber_id": "my-service",
  "system_ids": [30000142],
  "callback_url": "https://my-service.com/webhook"
}
```

## Response Format

### Success Response

```json
{
  "data": { ... },
  "timestamp": "2024-01-15T15:00:00Z",
  "error": null
}
```

### Error Response

```json
{
  "data": null,
  "error": "Error message",
  "code": "ERROR_CODE",
  "details": { ... },
  "timestamp": "2024-01-15T15:00:00Z"
}
```

## Kill Object Structure

```json
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
```

## HTTP Status Codes

| Code | Description    |
| ---- | -------------- |
| 200  | Success        |
| 400  | Bad Request    |
| 404  | Not Found      |
| 429  | Rate Limited   |
| 500  | Internal Error |

## Error Codes

| Code                | Description               |
| ------------------- | ------------------------- |
| `INVALID_PARAMETER` | Invalid request parameter |
| `NOT_FOUND`         | Resource not found        |
| `RATE_LIMITED`      | Rate limit exceeded       |
| `INTERNAL_ERROR`    | Server error              |
| `TIMEOUT`           | Request timeout           |

## Webhook Payload

### Kill Update

```json
{
  "type": "detailed_kill_update",
  "data": {
    "solar_system_id": 30000142,
    "kills": [...],
    "timestamp": "2024-01-15T15:00:00Z"
  }
}
```

### Count Update

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

### Create Subscription

```bash
curl -X POST http://localhost:4004/api/v1/subscriptions \
  -H "Content-Type: application/json" \
  -d '{"subscriber_id":"test","system_ids":[30000142],"callback_url":"https://example.com/hook"}'
```

### Health Check

```bash
curl http://localhost:4004/health
```
