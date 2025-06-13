defmodule WandererKills.Subscriptions.SystemIndex do
  @moduledoc """
  Maintains an ETS-based index for fast system -> subscription lookups.

  This module provides O(1) lookups to find all subscriptions interested
  in a specific system ID, maintaining performance parity with character
  subscriptions for high-throughput scenarios.

  ## Architecture

  Now built on the unified BaseIndex implementation, providing:
  1. **Forward Index (ETS)**: `system_id => MapSet[subscription_ids]`
  2. **Reverse Index (Map)**: `subscription_id => [system_ids]`

  This dual structure enables efficient operations:
  - Fast system lookups via ETS
  - Efficient subscription cleanup via reverse index
  - Atomic updates for subscription changes

  ## Performance Characteristics

  - **O(1) system lookups** using ETS table
  - **O(n) subscription updates** where n = system count
  - **Batch operations** for multiple system lookups
  - **Memory efficient** using MapSets to deduplicate subscription IDs

  ## Telemetry & Monitoring

  Emits `[:wanderer_kills, :system, :index]` events for:
  - `:add` - Adding subscriptions to index
  - `:remove` - Removing subscriptions from index
  - `:update` - Updating subscription system lists
  - `:lookup` - Single system lookups
  - `:batch_lookup` - Multiple system lookups

  Each event includes duration and relevant metadata for performance monitoring.

  ## Usage Example

      # Add a subscription
      SystemIndex.add_subscription("sub_123", [30000142, 30000144])

      # Find subscriptions for a system
      subs = SystemIndex.find_subscriptions_for_entity(30000142)
      # => ["sub_123"]

      # Batch lookup for multiple systems
      subs = SystemIndex.find_subscriptions_for_entities([30000142, 30000144])
      # => ["sub_123"]

      # Update subscription
      SystemIndex.update_subscription("sub_123", [30000142, 30000999])

      # Remove subscription
      SystemIndex.remove_subscription("sub_123")
  """

  use WandererKills.Subscriptions.BaseIndex,
    entity_type: :system,
    table_name: :system_subscription_index
end
