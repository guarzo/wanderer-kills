# WandererKills

A high-performance, real-time EVE Online killmail data service built with Elixir/Phoenix. This service provides REST API, WebSocket, and webhook interfaces for accessing killmail data from zKillboard.

## Features

- **Real-time Data** - Continuous killmail stream from zKillboard RedisQ
- **Multiple Integration Methods** - REST API, WebSocket, webhooks, and Phoenix PubSub
- **Efficient Caching** - Multi-tiered caching with Cachex for optimal performance
- **ESI Enrichment** - Automatic enrichment with character, corporation, and ship names
- **Batch Processing** - Efficient bulk operations for multiple systems
- **Event Streaming** - Optional event-driven architecture with offset tracking
- **Comprehensive Monitoring** - 5-minute status reports with system-wide metrics

## Quick Start

### Using Docker

```bash
# Run the service
docker run -p 4004:4004 wanderer-kills

# With persistent cache
docker run -p 4004:4004 \
  -v wanderer-cache:/app/cache \
  wanderer-kills
```

### Using Docker Compose

```bash
# Start all services (includes Redis)
docker-compose up

# Run in background
docker-compose up -d
```

### Development Setup

1. **Prerequisites**
   - Elixir 1.14.0+
   - OTP 25.0+
   - Docker (for Redis)

2. **Clone and Setup**

   ```bash
   git clone https://github.com/wanderer-industries/wanderer-kills.git
   cd wanderer-kills
   mix deps.get
   mix compile
   ```

3. **Start Services**

   ```bash
   # Start Redis
   docker run -d -p 6379:6379 redis:7-alpine

   # Start the application
   mix phx.server
   ```

The service will be available at `http://localhost:4004`

## API Overview

### REST Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/kills/system/{system_id}` | Get kills for a system |
| POST | `/api/v1/kills/systems` | Bulk fetch multiple systems |
| GET | `/api/v1/kills/cached/{system_id}` | Get cached kills only |
| GET | `/api/v1/killmail/{killmail_id}` | Get specific killmail |
| GET | `/api/v1/kills/count/{system_id}` | Get kill count |
| POST | `/api/v1/subscriptions` | Create webhook subscription |
| GET | `/health` | Health check |
| GET | `/status` | Service status |

### WebSocket Connection

```javascript
// Connect to WebSocket
const ws = new WebSocket('ws://localhost:4004/ws');

// Subscribe to systems
ws.send(JSON.stringify({
  action: 'subscribe',
  systems: [30000142, 30000144]
}));

// Receive real-time updates
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('New kill:', data);
};
```

### Example API Call

```bash
# Get kills for Jita in the last 24 hours
curl "http://localhost:4004/api/v1/kills/system/30000142?since_hours=24&limit=50"
```

## Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│   zKillboard   │────▶│    RedisQ    │────▶│  Processor  │
│     RedisQ     │     │   Consumer   │     │   Pipeline  │
└─────────────────┘     └──────────────┘     └─────────────┘
                                                     │
                              ┌──────────────────────┴───────────────┐
                              │                                      │
                              ▼                                      ▼
                    ┌─────────────────┐                    ┌─────────────────┐
                    │   ESI Enricher  │                    │  Storage Layer  │
                    │ (Names & Data)  │                    │  (ETS Tables)   │
                    └─────────────────┘                    └─────────────────┘
                              │                                      │
                              └──────────────┬───────────────────────┘
                                             ▼
                              ┌──────────────────────────┐
                              │    Distribution Layer    │
                              ├──────────────────────────┤
                              │ • REST API               │
                              │ • WebSocket              │
                              │ • Webhooks               │
                              │ • Phoenix PubSub         │
                              └──────────────────────────┘
```

### Key Components

- **RedisQ Consumer** - Continuously polls zKillboard for new killmails
- **Unified Processor** - Handles both full and partial killmail formats
- **ESI Enricher** - Adds character, corporation, and ship names
- **Storage Layer** - ETS-based storage with optional event streaming
- **Cache Layer** - Multi-tiered caching with configurable TTLs
- **Distribution Layer** - Multiple integration methods for consumers

## Configuration

### Environment Variables

```bash
# Port configuration
PORT=4004

# Redis configuration (optional)
REDIS_URL=redis://localhost:6379

# ESI configuration
ESI_BASE_URL=https://esi.evetech.net/latest
ESI_DATASOURCE=tranquility

# Cache TTLs (in seconds)
CACHE_KILLMAIL_TTL=300
CACHE_SYSTEM_TTL=3600
CACHE_ESI_TTL=86400
```

### Application Configuration

```elixir
# config/config.exs
config :wanderer_kills,
  port: 4004,
  redisq_base_url: "https://zkillredisq.stream/listen.php",
  storage: [
    enable_event_streaming: true
  ],
  cache: [
    default_ttl: :timer.minutes(5),
    cleanup_interval: :timer.minutes(10)
  ]
```

## Monitoring

The service provides comprehensive monitoring with 5-minute status reports:

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

### Health Monitoring

- **Health Check**: `GET /health` - Basic service health
- **Status Endpoint**: `GET /status` - Detailed service metrics
- **Telemetry Events**: Integration with Prometheus/StatsD
- **Structured Logging**: Extensive metadata for debugging

## Development

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test.coverage

# Run specific test file
mix test test/wanderer_kills/killmails/store_test.exs
```

### Code Quality

```bash
# Format code
mix format

# Run static analysis
mix credo --strict

# Run type checking
mix dialyzer

# Run all checks
mix check
```

### Development Container

The project includes VS Code development container support:

1. Install [Docker](https://docs.docker.com/get-docker/) and [VS Code](https://code.visualstudio.com/)
2. Install the [Remote - Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension
3. Open the project in VS Code
4. Click "Reopen in Container" when prompted

The development container includes all required tools and dependencies.

## Data Management

### Ship Type Data

The service requires ship type data for enrichment:

```bash
# Data is automatically loaded on first run
# Manual update if needed:
mix run -e "WandererKills.ShipTypes.Updater.update_all_ship_types()"
```

### Cache Management

```bash
# Clear all caches
mix run -e "Cachex.clear(:wanderer_cache)"

# Check cache statistics
mix run -e "IO.inspect(Cachex.stats(:wanderer_cache))"
```

## Documentation

Comprehensive documentation is available in the `/docs` directory:

- [API Reference](docs/api-reference.md) - Complete API documentation
- [Integration Guide](docs/integration-guide.md) - Integration examples and best practices
- [Architecture Overview](CLAUDE.md) - Detailed architecture documentation
- [Code Review](CODE_REVIEW.md) - Recent refactoring documentation

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`mix test`)
5. Check code quality (`mix credo --strict`)
6. Commit your changes (`git commit -m 'Add support for amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Development Guidelines

- Follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
- Write comprehensive tests for new features
- Update documentation for API changes
- Use descriptive commit messages
- Keep PRs focused and atomic

## Deployment

### Docker Production Build

```bash
# Build production image
docker build -t wanderer-kills:latest .

# Run with environment variables
docker run -d \
  -p 4004:4004 \
  -e PORT=4004 \
  -e REDIS_URL=redis://redis:6379 \
  --name wanderer-kills \
  wanderer-kills:latest
```

### Kubernetes

See [deployment/k8s/](deployment/k8s/) for Kubernetes manifests.

## Performance

The service is designed for high performance:

- **Concurrent Processing** - Leverages Elixir's actor model
- **Efficient Caching** - Multi-tiered cache with smart TTLs
- **Batch Operations** - Bulk enrichment and processing
- **Connection Pooling** - Optimized HTTP client connections
- **ETS Storage** - In-memory storage for fast access

Typical performance metrics:

- Process 100+ kills/second
- Cache hit rate > 85%
- API response time < 50ms (cached)
- WebSocket latency < 10ms

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [zKillboard](https://zkillboard.com/) for providing the killmail data
- [EVE Online](https://www.eveonline.com/) and CCP Games
- The Elixir/Phoenix community

## Support

- **Issues**: [GitHub Issues](https://github.com/wanderer-industries/wanderer-kills/issues)
- **Discussions**: [GitHub Discussions](https://github.com/wanderer-industries/wanderer-kills/discussions)
- **Email**: [wanderer-kills@proton.me](mailto:wanderer-kills@proton.me)

---

Built with ❤️ by [Wanderer Industries](https://github.com/wanderer-industries)
