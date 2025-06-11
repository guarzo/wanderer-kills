# WandererKills

A high-performance, real-time EVE Online killmail data service built with Elixir/Phoenix. This service provides REST API and WebSocket interfaces for accessing killmail data from zKillboard.

## Features

- **Real-time Data** - Continuous killmail stream from zKillboard RedisQ
- **Multiple Integration Methods** - REST API, WebSocket channels, and Phoenix PubSub
- **Efficient Caching** - Multi-tiered caching with custom ETS-based cache for optimal performance
- **ESI Enrichment** - Automatic enrichment with character, corporation, and ship names
- **Batch Processing** - Efficient bulk operations for multiple systems
- **Event Streaming** - Optional event-driven architecture with offset tracking
- **Comprehensive Monitoring** - 5-minute status reports with system-wide metrics

## Quick Start

### Using Docker

```bash
# Run the service
docker run -p 4004:4004 guarzo/wanderer-kills

# With environment variables
docker run -p 4004:4004 \
  -e PORT=4004 \
  -e ESI_BASE_URL=https://esi.evetech.net/latest \
  guarzo/wanderer-kills
```

### Using Docker Compose

```bash
# Start the service
docker-compose up

# Run in background
docker-compose up -d
```

### Development Setup

1. **Prerequisites**
   - Elixir 1.18+
   - OTP 25.0+

2. **Clone and Setup**

   ```bash
   git clone https://github.com/wanderer-industries/wanderer-kills.git
   cd wanderer-kills
   mix deps.get
   mix compile
   ```

3. **Start the Application**

   ```bash
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
| GET | `/health` | Health check |
| GET | `/status` | Service status |
| GET | `/websocket` | WebSocket connection info |

### WebSocket Connection

```javascript
// Import Phoenix Socket library
import { Socket } from 'phoenix';

// Connect to WebSocket
const socket = new Socket('ws://localhost:4004/socket', {
  params: { client_identifier: 'my_client' }
});

socket.connect();

// Join a killmail channel for a specific system
const channel = socket.channel('killmails:system:30000142', {});

channel.join()
  .receive('ok', resp => { console.log('Joined successfully', resp) })
  .receive('error', resp => { console.log('Unable to join', resp) });

// Listen for new kills
channel.on('new_kill', payload => {
  console.log('New kill:', payload);
});

// Subscribe to multiple systems
const systems = [30000142, 30000144];
channel.push('subscribe', { systems: systems })
  .receive('ok', resp => { console.log('Subscribed to systems', resp) });
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
                              │ • WebSocket Channels     │
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

The service uses an ETS-based caching system that is automatically managed. Caches are cleared and warmed on startup, with configurable TTLs for different data types.

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
  -e ESI_BASE_URL=https://esi.evetech.net/latest \
  --name wanderer-kills \
  guarzo/wanderer-kills:latest
```

## Performance

The service is designed for high performance:

- **Concurrent Processing** - Leverages Elixir's actor model
- **Efficient Caching** - Multi-tiered cache with smart TTLs
- **Batch Operations** - Bulk enrichment and processing
- **Connection Pooling** - Optimized HTTP client connections
- **ETS Storage** - In-memory storage for fast access

The service is optimized for:

- High-throughput kill processing
- Efficient batch operations
- Low-latency WebSocket updates
- Minimal API response times with caching

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
