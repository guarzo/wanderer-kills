defmodule WandererKills.Subscriptions.CharacterIndexNew do
  @moduledoc """
  Maintains an ETS-based index for fast character -> subscription lookups.
  
  This module uses the BaseIndex shared implementation to provide O(1) lookups
  for character-based subscription matching with performance parity to the
  system subscription implementation.
  
  ## Features
  
  - **O(1 character lookups** using ETS table
  - **Batch character processing** for multiple lookups
  - **Automatic telemetry** for performance monitoring
  - **Memory efficient** using MapSets for deduplication
  - **Periodic cleanup** of empty entries
  
  ## Usage
  
      # Single character lookup
      subs = CharacterIndexNew.find_subscriptions_for_entity(123456)
      
      # Batch character lookup  
      subs = CharacterIndexNew.find_subscriptions_for_entities([123456, 789012])
      
      # Subscription management
      CharacterIndexNew.add_subscription("sub_1", [123456, 789012])
      CharacterIndexNew.update_subscription("sub_1", [123456, 999999])
      CharacterIndexNew.remove_subscription("sub_1")
  """
  
  use WandererKills.Subscriptions.BaseIndex,
    entity_type: :character,
    table_name: :character_subscription_index_new
end