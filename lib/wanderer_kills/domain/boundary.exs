defmodule WandererKills.Domain.Boundary do
  @moduledoc """
  Boundary definition for the Domain context.

  The Domain context contains the core domain models and data structures
  that represent the business entities of the application. This context
  is purely data-focused and has no dependencies on other contexts.

  ## Responsibilities
  - Domain model definitions (Killmail, Victim, Attacker, etc.)
  - Data conversion and transformation utilities
  - Domain-specific validation logic
  - Type definitions for business entities

  ## Dependencies
  None - this is a pure domain layer

  ## Public API
  All modules in this context are designed to be used by other contexts:
  """

  use Boundary,
    deps: [],
    exports: [
      # Core domain models
      WandererKills.Domain.Killmail,
      WandererKills.Domain.Victim,
      WandererKills.Domain.Attacker,
      WandererKills.Domain.ZkbMetadata,

      # Data conversion utilities
      WandererKills.Domain.Converter
    ]
end
