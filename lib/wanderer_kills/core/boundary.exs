defmodule WandererKills.Core.Boundary do
  @moduledoc """
  Boundary definition for the Core context.

  The Core context provides shared infrastructure and foundational services
  used across all other contexts. It is the only context that can be depended
  upon by all other contexts.

  ## Responsibilities
  - Caching infrastructure
  - Storage abstractions
  - Observability and monitoring
  - Support utilities and common patterns
  - Application configuration
  - Error handling patterns
  - Ship type management

  ## Public API
  Only the following modules should be used by other contexts:
  """

  use Boundary,
    deps: [],
    exports: [
      # Cache API
      WandererKills.Core.Cache,

      # Storage API
      WandererKills.Core.Storage.KillmailStore,

      # Support utilities
      WandererKills.Core.Support.Error,
      WandererKills.Core.Support.SupervisedTask,
      WandererKills.Core.Support.BatchProcessor,
      WandererKills.Core.Support.Retry,
      WandererKills.Core.Support.PubSubTopics,

      # Ship Types API
      WandererKills.Core.ShipTypes.Cache,
      WandererKills.Core.ShipTypes.Info,

      # Configuration
      WandererKills.Config,

      # Types
      WandererKills.Core.Types,

      # Observability (read-only access for other contexts)
      WandererKills.Core.Observability.ApiTracker,
      WandererKills.Core.Observability.WebSocketStats,
      WandererKills.Core.Observability.Telemetry,

      # ETS management
      WandererKills.Core.EtsOwner
    ]
end
