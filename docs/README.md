# WandererKills Documentation

Welcome to the WandererKills service documentation. This directory contains comprehensive guides for integrating with the killmail data service.

## Documentation Overview

### 📖 [Integration Guide](integration-guide.md)

**Complete integration documentation** - Start here for comprehensive information on integrating with WandererKills service.

**Covers:**

- REST API integration with examples
- WebSocket integration for real-time updates
- Webhook configuration and handling
- Real-time PubSub integration (Elixir apps)
- Client library usage
- Error handling and best practices
- Code examples in Python, Node.js, and Elixir

### 📋 [API Reference](api-reference.md)

**Quick reference documentation** - Ideal for developers who need quick lookups during implementation.

**Includes:**

- Endpoint summaries
- Request/response formats
- Error codes and handling
- WebSocket message formats
- cURL examples
- Data structure definitions

## Quick Start

1. **For HTTP/REST integration**: Start with the [Integration Guide](integration-guide.md#rest-api-integration)
2. **For WebSocket real-time data**: See [WebSocket Integration](integration-guide.md#websocket-integration)
3. **For webhook subscriptions**: See [Webhook Integration](integration-guide.md#webhook-integration)
4. **For Elixir applications**: Review [Real-time Integration](integration-guide.md#real-time-integration-elixir-applications)
5. **For quick reference**: Use the [API Reference](api-reference.md)

## Service Overview

The WandererKills service provides:

- **REST API** - HTTP endpoints for fetching killmail data
- **WebSocket Connections** - Real-time kill notifications
- **Subscriptions** - Webhook notifications for system updates
- **PubSub** - Direct message broadcasting for Elixir applications
- **Client Library** - Behaviour-based integration for Elixir projects

## Common Integration Patterns

### 1. Polling Integration

Periodically fetch kills using REST endpoints. Good for:

- Batch processing
- Systems with relaxed real-time requirements
- Simple integrations

### 2. WebSocket Integration

Establish persistent connection for real-time kill updates. Good for:

- Real-time dashboards
- Low-latency applications
- Interactive user interfaces

### 3. Webhook Integration

Subscribe to receive HTTP callbacks when new kills are detected. Good for:

- External services
- Event-driven architectures
- Systems behind firewalls

### 4. PubSub Integration

Direct subscription to internal message broadcasts. Good for:

- Elixir applications in the same environment
- Low-latency requirements
- High-throughput scenarios

### 5. Client Library Integration

Use the provided Elixir behaviour for type-safe integration. Good for:

- Elixir applications
- Compile-time interface validation
- Consistent API across implementations

## Architecture Highlights

### Data Processing Pipeline
- **RedisQ Consumer** - Real-time killmail stream from zKillboard
- **Unified Processor** - Handles both full and partial killmails
- **Batch Enrichment** - Efficient ESI data enrichment
- **Storage Layer** - ETS-based storage with optional event streaming

### Caching Strategy
- Single Cachex instance (`:wanderer_cache`) with namespaced keys
- Configurable TTLs: killmails (5min), systems (1hr), ESI data (24hr)
- Ship type data preloaded from CSV files

### Error Handling
- Standardized error responses using `Support.Error` module
- Consistent `{:ok, result}` / `{:error, %Error{}}` patterns
- Structured error codes and messages

## Monitoring & Observability

The service provides comprehensive monitoring:

- **Health Check**: Monitor service status at `GET /health`
- **Status Endpoint**: Detailed metrics at `GET /status`
- **5-Minute Status Reports**: Comprehensive system-wide statistics in logs
- **Telemetry Events**: Integration with monitoring tools
- **Structured Logging**: Extensive metadata for debugging

## Getting Help

- **Issues**: Report bugs or request features via GitHub issues
- **API Reference**: Quick lookups in [api-reference.md](api-reference.md)
- **Examples**: Comprehensive examples in [integration-guide.md](integration-guide.md)
- **Health Check**: Monitor service status at `GET /health`

## Service Information

- **Default Port**: 4004
- **API Version**: v1
- **Base URL**: `http://localhost:4004/api/v1`
- **Health Endpoint**: `http://localhost:4004/health`
- **Status Endpoint**: `http://localhost:4004/status`

## External Dependencies

The service integrates with:

- **zKillboard RedisQ** - Real-time killmail stream
- **EVE ESI API** - Killmail details and validation

Rate limiting and caching are implemented to ensure reliable operation while respecting external service limits.

## Recent Updates (2025-01-06)

The service has undergone significant refactoring for improved consistency and maintainability:

- **Unified Storage**: Consolidated storage layer with optional event streaming
- **Standardized Naming**: Consistent `killmail` terminology and naming patterns
- **Enhanced Monitoring**: Comprehensive 5-minute status reports
- **Improved Error Handling**: Standardized error responses across all endpoints
- **WebSocket Support**: Added real-time WebSocket connections for kill updates

See [CODE_REVIEW.md](/CODE_REVIEW.md) for detailed refactoring documentation.