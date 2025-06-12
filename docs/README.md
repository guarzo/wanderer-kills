# WandererKills Documentation

Welcome to the WandererKills service documentation.

## 📖 [API & Integration Guide](API_AND_INTEGRATION_GUIDE.md)

**Complete documentation** - This is the primary documentation source for WandererKills service.

**Covers everything you need:**
- REST API endpoints with examples
- WebSocket real-time integration
- PubSub integration for Elixir apps  
- Client library usage
- Error handling and best practices
- Code examples in Python, Node.js, and Elixir
- Rate limiting and monitoring
- Troubleshooting guide

## Quick Start

1. **For HTTP/REST integration**: See [REST API Integration](API_AND_INTEGRATION_GUIDE.md#rest-api-integration)
2. **For WebSocket real-time data**: See [WebSocket Integration](API_AND_INTEGRATION_GUIDE.md#websocket-integration)
3. **For Elixir applications**: See [PubSub Integration](API_AND_INTEGRATION_GUIDE.md#pubsub-integration-elixir-applications)
4. **For client library usage**: See [Client Library Integration](API_AND_INTEGRATION_GUIDE.md#client-library-integration-elixir)

## Service Information

- **Default Port**: 4004
- **Base URL**: `http://localhost:4004/api/v1`
- **Health Check**: `http://localhost:4004/health`
- **Status Endpoint**: `http://localhost:4004/status`

## Common Integration Patterns

### 1. REST API (HTTP)
Best for batch processing and simple integrations.

### 2. WebSocket
Best for real-time dashboards and low-latency applications.

### 3. PubSub (Elixir)
Best for Elixir applications in the same environment requiring high throughput.

### 4. Client Library (Elixir)
Best for type-safe integration with compile-time interface validation.

## Getting Help

- **Comprehensive Guide**: [API_AND_INTEGRATION_GUIDE.md](API_AND_INTEGRATION_GUIDE.md)
- **Health Check**: Monitor service status at `GET /health`
- **GitHub Issues**: Report bugs or request features