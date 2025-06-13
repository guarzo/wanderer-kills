defmodule WandererKills.Subscriptions.CharacterIndex do
  @moduledoc """
  Maintains an ETS-based index for fast character -> subscription lookups.

  This module provides O(1) lookups to find all subscriptions interested
  in a specific character ID, significantly improving performance when
  filtering killmails with many attackers.

  ## Architecture

  Now built on the unified BaseIndex implementation, providing:
  1. **Forward Index (ETS)**: `character_id => MapSet[subscription_ids]`
  2. **Reverse Index (Map)**: `subscription_id => [character_ids]`

  This dual structure enables efficient operations:
  - Fast character lookups via ETS
  - Efficient subscription cleanup via reverse index
  - Atomic updates for subscription changes

  ## Performance Characteristics

  - **O(1) character lookups** using ETS table
  - **O(n) subscription updates** where n = character count
  - **Batch operations** for multiple character lookups
  - **Memory efficient** using MapSets to deduplicate subscription IDs

  ## Telemetry & Monitoring

  Emits `[:wanderer_kills, :character, :index]` events for:
  - `:add` - Adding subscriptions to index
  - `:remove` - Removing subscriptions from index
  - `:update` - Updating subscription character lists
  - `:lookup` - Single character lookups
  - `:batch_lookup` - Multiple character lookups

  Each event includes duration and relevant metadata for performance monitoring.

  ## Health Monitoring

  The index provides statistics via `get_stats/0` including:
  - Total subscriptions indexed
  - Total character entries
  - Memory usage estimates

  Warnings are logged for:
  - Large subscription additions (>100 characters)
  - Index size approaching limits

  ## Usage Example

      # Add a subscription
      CharacterIndex.add_subscription("sub_123", [95465499, 90379338])

      # Find subscriptions for a character
      subs = CharacterIndex.find_subscriptions_for_entity(95465499)
      # => ["sub_123"]

      # Batch lookup for multiple characters
      subs = CharacterIndex.find_subscriptions_for_entities([95465499, 90379338])
      # => ["sub_123"]

      # Update subscription
      CharacterIndex.update_subscription("sub_123", [95465499, 12345678])

      # Remove subscription
      CharacterIndex.remove_subscription("sub_123")
  """

  use WandererKills.Subscriptions.BaseIndex,
    entity_type: :character,
    table_name: :character_subscription_index

end
