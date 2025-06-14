defmodule WandererKills.Subs.Subscriptions.SystemIndexUnifiedTest do
  @moduledoc """
  Unified test suite for SystemIndex using shared test patterns.

  This test file demonstrates the new standardized approach to testing
  subscription indexes, eliminating duplication while ensuring comprehensive
  coverage of all functionality.
  """

  use ExUnit.Case, async: false

  use IndexTestPatterns,
    index_module: WandererKills.Subs.Subscriptions.SystemIndex,
    health_module: WandererKills.Core.Observability.SystemSubscriptionHealth,
    # System IDs (Jita, Amarr, Rens)
    test_entities: [30_000_142, 30_000_144, 30_000_148]
end
