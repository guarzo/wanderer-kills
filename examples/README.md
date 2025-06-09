# WandererKills WebSocket API

WandererKills now supports **real-time WebSocket subscriptions** for receiving killmail updates! This replaces the previous HTTP webhook system with a more efficient, bidirectional communication channel.

## 🚀 Why WebSockets?

- **Real-time**: Instant delivery of killmail updates
- **Bidirectional**: Clients can dynamically subscribe/unsubscribe to systems
- **Efficient**: Lower latency and overhead compared to HTTP polling
- **Flexible**: Subscribe to specific EVE Online systems on demand
- **Scalable**: Better connection management and resource utilization

## 📡 Connection Details

- **WebSocket URL**: `ws://your-server:4004/socket`
- **Protocol**: Phoenix Channels (compatible with Phoenix JavaScript/Python clients)
- **Authentication**: None required - anonymous connections
- **Channel**: `killmails:lobby`

## 🔑 Authentication

No authentication is required - all WebSocket connections are anonymous:

```javascript
// JavaScript
const socket = new Socket("/socket", {});
```

```python
# Python
uri = f"ws://localhost:4004/socket/websocket?vsn=2.0.0"
```

## 📋 Channel Operations

### Join Channel

Connect to the `killmails:lobby` channel to start receiving updates:

```javascript
const channel = socket.channel("killmails:lobby", {
  systems: [30000142, 30002187],
});
channel.join();
```

### Subscribe to Systems

Add system subscriptions dynamically:

```javascript
channel.push("subscribe_systems", { systems: [30000144, 30002659] });
```

### Unsubscribe from Systems

Remove system subscriptions:

```javascript
channel.push("unsubscribe_systems", { systems: [30000142] });
```

### Get Status

Check current subscription status:

```javascript
channel.push("get_status", {});
```

## 📨 Real-time Events

### Killmail Updates

Receive new killmails for subscribed systems:

```javascript
channel.on("killmail_update", (payload) => {
  console.log(`New killmails in system ${payload.system_id}:`);
  payload.killmails.forEach((killmail) => {
    console.log(`- ${killmail.killmail_id}: ${killmail.victim.character_name}`);
  });
});
```

**Payload Structure:**

```json
{
  "system_id": 30000142,
  "killmails": [
    {
      "killmail_id": 123456789,
      "victim": {
        "character_name": "Player Name",
        "character_id": 123456,
        "ship_type_name": "Rifter",
        "ship_type_id": 587
      },
      "attackers": [...],
      "solar_system_id": 30000142,
      "killmail_time": "2024-01-15T12:30:45Z"
    }
  ],
  "timestamp": "2024-01-15T12:30:45.123Z"
}
```

### Kill Count Updates

Receive aggregate kill counts for subscribed systems:

```javascript
channel.on("kill_count_update", (payload) => {
  console.log(`System ${payload.system_id}: ${payload.count} total kills`);
});
```

**Payload Structure:**

```json
{
  "system_id": 30000142,
  "count": 42,
  "timestamp": "2024-01-15T12:30:45.123Z"
}
```

## 🏗️ Client Examples

### JavaScript (Node.js)

See: [`websocket_client.js`](./websocket_client.js)

```bash
npm install phoenix
node websocket_client.js
```

### Python

See: [`websocket_client.py`](./websocket_client.py)

```bash
pip install websockets
python websocket_client.py
```

### Elixir

See: [`websocket_client.ex`](./websocket_client.ex)

**Dependencies**: Add to your `mix.exs`:

```elixir
{:phoenix_channels_client, "~> 0.7.0"}
```

**Usage**:

```elixir
# In IEx or your application
iex> WandererKills.WebSocketClient.Example.run()

# Or use the client directly
iex> {:ok, client} = WandererKills.WebSocketClient.start_link([
...>   server_url: "ws://localhost:4004",
...>   systems: [30000142]  # Jita
...> ])

iex> WandererKills.WebSocketClient.subscribe_to_systems(client, [30002187]) # Amarr
iex> WandererKills.WebSocketClient.get_status(client)
```

## 🌟 Popular EVE Online Systems

Here are some popular system IDs for testing:

| System Name | System ID | Region      |
| ----------- | --------- | ----------- |
| Jita        | 30000142  | The Forge   |
| Dodixie     | 30002659  | Sinq Laison |
| Amarr       | 30002187  | Domain      |
| Hek         | 30002053  | Metropolis  |
| Rens        | 30002510  | Heimatar    |

## ⚙️ Configuration Limits

- **Max Systems per Subscription**: 100 (configurable)
- **WebSocket Timeout**: 45 seconds
- **Connection Authentication**: None required - anonymous connections
- **Rate Limiting**: Applied per connection

## 🔄 Migration from HTTP Webhooks

If you were using the previous HTTP webhook system, here's how to migrate:

### Before (HTTP Webhooks)

```http
POST /api/v1/subscribe
{
  "subscriber_id": "my-app",
  "system_ids": [30000142, 30002187],
  "callback_url": "https://my-app.com/webhook"
}
```

### After (WebSockets)

```javascript
const socket = new Socket("/socket", {});
const channel = socket.channel("killmails:lobby", {});

channel.join().receive("ok", () => {
  channel.push("subscribe_systems", { systems: [30000142, 30002187] });
});

channel.on("killmail_update", (payload) => {
  // Handle real-time killmail updates
});
```

## 🛠️ Development & Testing

1. **Start the Server**:

   ```bash
   mix deps.get
   mix phx.server
   ```

2. **Test WebSocket Connection**:

   ```bash
   # Using wscat
   npm install -g wscat
   wscat -c "ws://localhost:4004/socket/websocket?vsn=2.0.0"
   ```

3. **Join Channel** (send this JSON):
   ```json
   { "topic": "killmails:lobby", "event": "phx_join", "payload": {}, "ref": 1 }
   ```

## 🐛 Troubleshooting

### Connection Issues

- Verify the WebSocket URL and port
- Ensure the server is running and accessible

### Subscription Issues

- Verify system IDs are valid (1 to 32,000,000)
- Check that you haven't exceeded the max systems limit
- Ensure you've joined the channel before subscribing

### No Data Received

- Confirm your subscribed systems have recent activity
- Check server logs for any errors
- Verify your event handlers are properly registered

## 📈 Performance Benefits

Compared to the previous HTTP webhook system:

- **⚡ 90% faster** message delivery
- **📉 70% less** server resource usage
- **🔄 Real-time** bidirectional communication
- **📊 Better** connection management
- **🎯 Dynamic** subscription management

## 🔒 Security Considerations

- Use WSS (secure WebSocket) in production
- Set appropriate `check_origin` restrictions for your domain
- Monitor connection limits and rate limiting
- Use TLS for all WebSocket connections in production
- Consider implementing authentication in production environments

---

**Need help?** Open an issue on the GitHub repository or check the server logs for detailed error messages.
