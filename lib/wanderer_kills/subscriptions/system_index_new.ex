defmodule WandererKills.Subscriptions.SystemIndexNew do
  @moduledoc """
  Maintains an ETS-based index for fast system -> subscription lookups.
  
  This module uses the BaseIndex shared implementation to provide O(1) lookups
  for system-based subscription matching with performance parity to the
  character subscription implementation.
  
  ## Features
  
  - **O(1 system lookups** using ETS table
  - **Batch system processing** for multiple lookups
  - **Automatic telemetry** for performance monitoring
  - **Memory efficient** using MapSets for deduplication
  - **Periodic cleanup** of empty entries
  
  ## Usage
  
      # Single system lookup
      subs = SystemIndexNew.find_subscriptions_for_entity(30000142)
      
      # Batch system lookup  
      subs = SystemIndexNew.find_subscriptions_for_entities([30000142, 30000144])
      
      # Subscription management
      SystemIndexNew.add_subscription("sub_1", [30000142, 30000144])
      SystemIndexNew.update_subscription("sub_1", [30000142, 30000999])
      SystemIndexNew.remove_subscription("sub_1")
  """
  
  use WandererKills.Subscriptions.BaseIndex,
    entity_type: :system,
    table_name: :system_subscription_index_new
end