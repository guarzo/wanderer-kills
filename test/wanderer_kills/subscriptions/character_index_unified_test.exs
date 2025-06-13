defmodule WandererKills.Subscriptions.CharacterIndexUnifiedTest do
  @moduledoc """
  Unified test suite for CharacterIndexNew using shared test patterns.
  
  This test file demonstrates the new standardized approach to testing
  subscription indexes, eliminating duplication while ensuring comprehensive
  coverage of all functionality.
  """
  
  use ExUnit.Case, async: false
  use IndexTestPatterns,
    index_module: WandererKills.Subscriptions.CharacterIndexNew,
    health_module: WandererKills.Observability.CharacterSubscriptionHealthNew,
    test_entities: [123_456, 789_012, 345_678]  # Character IDs
end