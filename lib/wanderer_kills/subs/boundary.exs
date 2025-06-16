defmodule WandererKills.Subs.Boundary do
  @moduledoc """
  Boundary definition for the Subs context.

  The Subs context handles subscription management and killmail delivery
  to various subscribers (WebSocket, webhooks). It manages subscription
  lifecycle, filtering, and broadcasting.

  ## Responsibilities
  - WebSocket and webhook subscription management
  - Subscription indexing and lookup
  - Killmail filtering and delivery
  - Preloading historical data for new subscriptions
  - Broadcasting killmail updates
  - Subscription health monitoring

  ## Dependencies
  - Core: For storage, caching, error handling, and utilities
  - Domain: For killmail models and filtering
  - Ingest: For character matching and batch processing

  ## Public API
  Only the following modules should be used by other contexts:
  """

  use Boundary,
    deps: [
      WandererKills.Core,
      WandererKills.Domain,
      WandererKills.Ingest
    ],
    exports: [
      # Main subscription management
      WandererKills.Subs.SubscriptionManager,

      # Preloading service
      WandererKills.Subs.Preloader,

      # Subscription indices (for lookups)
      WandererKills.Subs.Subscriptions.CharacterIndex,
      WandererKills.Subs.Subscriptions.SystemIndex,

      # Filtering utilities
      WandererKills.Subs.Subscriptions.Filter,

      # Broadcasting service
      WandererKills.Subs.Subscriptions.Broadcaster,

      # Registry for process management
      WandererKills.Subs.SubscriptionRegistry
    ]
end
