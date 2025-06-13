defmodule WandererKills.Subscriptions.CharacterIndexUnifiedTest do
  @moduledoc """
  Unified test suite for CharacterIndex using shared test patterns.

  This test file demonstrates the new standardized approach to testing
  subscription indexes, eliminating duplication while ensuring comprehensive
  coverage of all functionality.
  """

  use ExUnit.Case, async: false

  use IndexTestPatterns,
    index_module: WandererKills.Subscriptions.CharacterIndex,
    health_module: WandererKills.Observability.CharacterSubscriptionHealth,
    # Character IDs
    test_entities: [123_456, 789_012, 345_678]
end
