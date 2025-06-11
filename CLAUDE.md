# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WandererKills is a real-time EVE Online killmail data service built with Elixir/Phoenix that:

- Fetches killmail data from zKillboard API  
- Provides caching and enrichment of killmail data with ESI (EVE Swagger Interface)
- Offers REST API endpoints and WebSocket support for real-time updates
- Uses ETS-based storage with event streaming capabilities

## Essential Commands

### Development
```bash
mix deps.get              # Install dependencies
mix compile              # Compile the project
mix phx.server           # Start Phoenix server (port 4004)
iex -S mix phx.server    # Start with interactive shell
```

### Testing
```bash
mix test                 # Run all tests
mix test path/to/test.exs  # Run specific test file
mix test path/to/test.exs:42  # Run specific test at line 42
mix test.coverage        # Generate HTML coverage report
mix test.coverage.ci     # Generate JSON coverage for CI
```

### Code Quality
```bash
mix format               # Format code
mix credo --strict      # Run static analysis
mix dialyzer           # Run type checking
mix check             # Run format check, credo, and dialyzer
```

### Docker Development
```bash
docker build -t wanderer-kills-dev -f Dockerfile.dev .
docker-compose up        # Start with Redis and all services
```

## Architecture Overview

### Core Components

1. **OTP Application** (`WandererKills.App.Application`)
   - Supervises all child processes
   - Manages Cachex, Phoenix endpoint, and data fetchers
   - Handles telemetry and monitoring

2. **Data Flow Pipeline**
   - `RedisQ` - Real-time killmail stream consumer from zKillboard
   - `ZkbClient` - Historical data fetcher for specific queries
   - `UnifiedProcessor` - Processes both full and partial killmails
   - `Storage.KillmailStore` - ETS-based storage with event streaming
   - `ESI.DataFetcher` - Enriches data with EVE API information

3. **Caching Layer**
   - Single Cachex instance (`:wanderer_cache`) with namespace support
   - TTL configuration: killmails (5min), systems (1hr), ESI data (24hr)
   - Ship type data pre-loaded from CSV files

4. **API & Real-time**
   - REST endpoints via Phoenix Router
   - WebSocket channels for live subscriptions
   - Standardized error responses using `Support.Error`

5. **Observability**
   - 5-minute status reports with comprehensive metrics
   - Telemetry events for all major operations
   - Structured logging with metadata
   - Health check endpoints for monitoring

### Module Organization

#### Core Business Logic
- `Killmails.UnifiedProcessor` - Main killmail processing logic
- `Killmails.Pipeline.*` - Processing pipeline stages (Parser, Validator, Enricher)
- `Killmails.Transformations` - Data normalization and transformations
- `Storage.KillmailStore` - Unified storage with event streaming

#### External Services
- `ESI.DataFetcher` - EVE Swagger Interface client
- `Killmails.ZkbClient` - zKillboard API client
- `RedisQ` - Real-time data stream consumer
- `Http.Client` - Centralized HTTP client with rate limiting

#### Support Infrastructure
- `Support.SupervisedTask` - Supervised async tasks with telemetry
- `Support.Error` - Standardized error structures
- `Support.Retry` - Configurable retry logic
- `Support.BatchProcessor` - Parallel batch processing

#### Subscriptions & Broadcasting
- `SubscriptionManager` - Manages WebSocket and webhook subscriptions
- `Subscriptions.Broadcaster` - PubSub message broadcasting
- `Subscriptions.WebhookNotifier` - HTTP webhook delivery
- `Subscriptions.Preloader` - Historical data preloading

#### Ship Types Management
- `ShipTypes.CSV` - Orchestrates CSV data loading
- `ShipTypes.Parser` - CSV parsing and extraction
- `ShipTypes.Validator` - Data validation rules
- `ShipTypes.Cache` - Ship type caching operations

#### Health & Monitoring
- `Observability.HealthChecks` - Unified health check interface
- `Observability.ApplicationHealth` - Application metrics
- `Observability.CacheHealth` - Cache performance metrics
- `Observability.WebSocketStats` - Real-time connection statistics

## Key Design Patterns

### Behaviours for Testability
All external service clients implement behaviours, allowing easy mocking in tests:
- `Http.ClientBehaviour` - HTTP client interface
- `ESI.ClientBehaviour` - ESI API interface  
- `Observability.HealthCheckBehaviour` - Health check interface

### Supervised Async Work
All async operations use `Support.SupervisedTask`:
```elixir
SupervisedTask.start_child(
  fn -> process_data() end,
  task_name: "process_data",
  metadata: %{data_id: id}
)
```

### Standardized Error Handling
All errors use `Support.Error` for consistency:
```elixir
{:error, Error.http_error(:timeout, "Request timed out", true)}
{:error, Error.validation_error(:invalid_format, "Invalid data")}
```

### Event-Driven Architecture
- Phoenix PubSub for internal communication
- Storage events for data changes
- Telemetry events for monitoring

## Common Development Tasks

### Adding New API Endpoints
1. Define route in `router.ex`
2. Create controller action
3. Implement context function
4. Add tests for both layers

### Adding External Service Clients
1. Define behaviour in `client_behaviour.ex`
2. Implement client using `Http.Client`
3. Configure mock in test environment
4. Use dependency injection via config

### Processing Pipeline Extensions
1. Add new stage in `pipeline/` directory
2. Implement behaviour callbacks
3. Update `UnifiedProcessor` to include stage
4. Add comprehensive tests

### Health Check Extensions
1. Implement `HealthCheckBehaviour`
2. Add to health check aggregator
3. Define metrics and thresholds
4. Test failure scenarios

## Configuration Patterns

### Environment Configuration
- Base: `config/config.exs`
- Environment: `config/{dev,test,prod}.exs`
- Runtime: `config/runtime.exs`
- Access via: `WandererKills.Config`

### Feature Flags
- Event streaming: `:storage, :enable_event_streaming`
- RedisQ start: `:start_redisq`
- Monitoring intervals: `:monitoring, :status_interval_ms`

## Best Practices

### Naming Conventions
- Use `killmail` consistently (not `kill`)
- `get_*` for cache/local operations
- `fetch_*` for external API calls
- `list_*` for collections
- `_async` suffix for async operations

### Cache Keys
- Killmails: `"killmail:{id}"`
- Systems: `"system:{id}"`  
- ESI data: `"esi:{type}:{id}"`
- Ship types: `"ship_types:{id}"`

### Testing Strategy
- Mock external services via behaviours
- Test public APIs, not implementation
- Use factories for test data
- Comprehensive error case coverage

### Performance Considerations
- Batch operations when possible
- Use ETS for high-frequency reads
- Implement circuit breakers for external services
- Monitor memory usage of GenServers

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.