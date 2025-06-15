defmodule WandererKillsWeb.Boundary do
  @moduledoc """
  Boundary definition for the Web context.

  The Web context handles HTTP API endpoints, WebSocket connections,
  and all web-related functionality. It provides REST APIs and real-time
  WebSocket connections for killmail subscriptions.

  ## Responsibilities
  - HTTP REST API endpoints
  - WebSocket channel management
  - Request validation and parameter parsing
  - API logging and monitoring
  - Health check endpoints
  - User authentication and session management

  ## Dependencies
  - Core: For error handling, observability, and utilities
  - Domain: For killmail models and data structures
  - Subs: For subscription management and WebSocket functionality

  ## Public API
  Only the following modules should be used by other contexts:
  """

  use Boundary,
    deps: [
      WandererKills.Core,
      WandererKills.Domain,
      WandererKills.Subs
    ],
    exports: [
      # Phoenix Endpoint
      WandererKillsWeb.Endpoint,

      # Router
      WandererKillsWeb.Router,

      # WebSocket functionality
      WandererKillsWeb.UserSocket,
      WandererKillsWeb.KillmailChannel,

      # API utilities (for testing and integration)
      WandererKillsWeb.Api.Validators,
      WandererKillsWeb.Shared.Parsers
    ]
end