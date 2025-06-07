# WandererKills Documentation

Welcome to the WandererKills service documentation. This directory contains comprehensive guides for integrating with the killmail data service.

## Documentation Overview

### 📖 [Integration Guide](integration-guide.md)

**Complete integration documentation** - Start here for comprehensive information on integrating with WandererKills service.

**Covers:**

- REST API integration with examples
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
- Error codes
- cURL examples
- Data structure definitions

## Quick Start

1. **For HTTP/REST integration**: Start with the [Integration Guide](integration-guide.md#rest-api-integration)
2. **For webhook subscriptions**: See [Webhook Integration](integration-guide.md#webhook-integration)
3. **For Elixir applications**: Review [Real-time Integration](integration-guide.md#real-time-integration-elixir-applications)
4. **For quick reference**: Use the [API Reference](api-reference.md)

## Service Overview

The WandererKills service provides:

- **REST API** - HTTP endpoints for fetching killmail data
- **Subscriptions** - Webhook notifications for real-time updates
- **PubSub** - Direct message broadcasting for Elixir applications
- **Client Library** - Behaviour-based integration for Elixir projects

## Common Integration Patterns

### 1. Polling Integration

Periodically fetch kills using REST endpoints. Good for:

- Batch processing
- Systems with relaxed real-time requirements
- Simple integrations

### 2. Webhook Integration

Subscribe to receive HTTP callbacks when new kills are detected. Good for:

- Real-time applications
- External services
- Event-driven architectures

### 3. PubSub Integration

Direct subscription to internal message broadcasts. Good for:

- Elixir applications in the same environment
- Low-latency requirements
- High-throughput scenarios

### 4. Client Library Integration

Use the provided Elixir behaviour for type-safe integration. Good for:

- Elixir applications
- Compile-time interface validation
- Consistent API across implementations

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
