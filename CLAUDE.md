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

1. **OTP Application Structure** (`WandererKills.App.Application`):
   - Supervises all child processes including Cachex, Phoenix endpoint, and data fetchers
   - Manages telemetry and monitoring

2. **Data Flow Pipeline**:
   - `RedisQ` → Real-time killmail stream consumer
   - `ZkbClient` → Historical data fetcher
   - `Pipeline` (Coordinator → Parser → Enricher) → Process killmails
   - `KillStore` → ETS-based storage with event streaming
   - `ESI.DataFetcher` → Enrichment with EVE API data

3. **Caching Strategy**:
   - Single Cachex instance with namespace support
   - Different TTLs: killmails (5min), systems (1hr), ESI data (24hr)
   - Cache warming for ship type data from CSV files

4. **API Layer**:
   - REST endpoints via Phoenix Router
   - WebSocket channels for real-time subscriptions
   - Standardized JSON responses with comprehensive error handling

### Key Design Patterns

- **Behaviour-based design**: All external clients have behaviours for testability
- **GenServer processes**: For stateful components (RedisQ, stores)
- **Phoenix PubSub**: Internal real-time communication
- **Task supervision**: Concurrent operations with fault tolerance
- **Circuit breakers**: For external API reliability

## Development Guidelines

### Elixir Best Practices

**Code Organization**
- Organize code around business domains using Domain-Driven Design
- Implement functional core with imperative shell pattern
- Use explicit code over implicit - clarity is paramount
- Favor composition over inheritance
- Each module and function should have single responsibility
- Design for changeability and maintainability
- Follow YAGNI principle - avoid unnecessary features

**Style Guidelines**
- Use 2 spaces for indentation, never tabs
- Unix-style line endings throughout
- Remove trailing whitespace
- Limit line length for readability
- Use snake_case for functions/variables/files
- Use PascalCase for modules and protocols
- Choose clear, descriptive names without abbreviations

**Functions and Modules**
- Use `def` for public, `defp` for private functions
- Keep modules small and focused on single concern
- Group related functions together
- Pattern match in function heads for different cases
- Use guard clauses for additional constraints

**Pipe Operator Usage**
- Chain functions with `|>` for linear data transformation
- Each pipe operation on its own line when chaining multiple
- Ensure clear data flow without interruptions
- Left side must provide correct input for next function

**Documentation**
- Document every public module with `@moduledoc`
- Document public functions with `@doc`
- Write inline comments only for non-obvious logic
- Keep documentation succinct yet informative
- Update docs as code evolves

### Phoenix-Specific Practices

- Use LiveView as primary UI technology for real-time features
- Implement function components for reusable UI elements
- Utilize Phoenix PubSub for real-time communication
- Respect context boundaries in controllers and LiveViews
- Keep controllers thin - delegate business logic to contexts
- Prioritize security (CSRF, XSS protection)

### Ecto Best Practices

- Use Ecto.Changeset for data validation at boundaries
- Implement proper error handling with result tuples
- Avoid N+1 queries - use preloading and joins
- Implement pagination for large result sets
- Use Ecto's type specifications for type safety

### GenServer and OTP

- Use GenServer for managing stateful processes
- Implement proper supervision trees
- Use Registry pattern for dynamic process lookup
- Use Task.Supervisor for concurrent, potentially failing operations
- Design processes to crash independently
- Embrace "let it crash" philosophy with proper supervision

### Testing Approach

- Focus on testing public APIs of contexts
- Use Mox for mocking external dependencies (all clients have behaviours)
- Use ExMachina for test data factories
- Write tests as documentation
- Structure tests with Arrange-Act-Assert pattern
- Test files in `test/` directory mirror `lib/` structure

### HTTP and External APIs

- Use Req library for HTTP client operations
- Define behaviours for all API clients
- Implement proper error handling for network failures
- Set appropriate timeouts for external calls
- Use circuit breakers for critical services
- All external clients are configurable via application config

### Error Handling

- Use pattern matching and guard clauses
- Return `{:ok, result}` or `{:error, reason}` tuples
- Favor explicit error handling over exceptions
- Implement fail-fast error handling
- Let processes crash when appropriate with supervision

## Project-Specific Patterns

### Cache Key Conventions
- Killmails: `"killmail:{id}"`
- Systems: `"system:{id}"`
- ESI data: `"esi:{type}:{id}"`

### Event Streaming
- KillStore publishes events with client offset tracking
- Supports both polling and push-based consumption
- Events include full killmail data and metadata

### Configuration
- Main config in `config/config.exs`
- Environment-specific in `config/{env}.exs`
- Runtime config in `config/runtime.exs`
- Test environment uses mocked clients

### Monitoring and Observability
- Telemetry events throughout the application
- Health check endpoint at `/health`
- Extensive logging with metadata
- Prometheus metrics support

## Common Development Tasks

### Adding New Endpoints
1. Define route in `lib/wanderer_kills_web/router.ex`
2. Create controller in `lib/wanderer_kills_web/controllers/`
3. Add context function in appropriate module under `lib/wanderer_kills/`
4. Write tests for both controller and context

### Working with External APIs
1. Define behaviour in `lib/wanderer_kills/{service}/client_behaviour.ex`
2. Implement client with Req library
3. Configure mock in test config
4. Use dependency injection via application config

### Modifying Kill Processing
1. Pipeline stages are in `lib/wanderer_kills/killmails/pipeline/`
2. Coordinator manages the flow
3. Parser handles initial validation
4. Enricher adds additional data
5. All stages use behaviours for testability