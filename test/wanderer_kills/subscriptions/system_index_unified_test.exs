defmodule WandererKills.Subscriptions.SystemIndexUnifiedTest do
  @moduledoc """
  Unified test suite for SystemIndexNew using shared test patterns.
  
  This test file demonstrates the new standardized approach to testing
  subscription indexes, eliminating duplication while ensuring comprehensive
  coverage of all functionality.
  """
  
  use ExUnit.Case, async: false
  use IndexTestPatterns,
    index_module: WandererKills.Subscriptions.SystemIndexNew,
    health_module: WandererKills.Observability.SystemSubscriptionHealthNew,
    test_entities: [30_000_142, 30_000_144, 30_000_148]  # System IDs (Jita, Amarr, Rens)
end