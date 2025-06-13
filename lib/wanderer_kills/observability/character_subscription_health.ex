defmodule WandererKills.Observability.CharacterSubscriptionHealth do
  @moduledoc """
  Health check implementation for character subscription components.
  
  This module provides comprehensive health monitoring for the character
  subscription system using the unified SubscriptionHealth implementation.
  It monitors the CharacterIndex performance, memory usage, and subscription
  volume with character-specific thresholds and test patterns.
  
  ## Health Checks
  
  - **Index Availability**: Verifies CharacterIndex GenServer is responding
  - **Performance**: Tests character lookup performance (target < 1ms)
  - **Memory Usage**: Monitors ETS table memory consumption  
  - **Subscription Volume**: Tracks character subscription counts
  
  ## Integration
  
  Integrates with ApplicationHealth to provide character subscription
  health status as part of overall application monitoring.
  
  ## Usage
  
      # Check health status
      health = CharacterSubscriptionHealth.check_health()
      
      # Get detailed metrics
      metrics = CharacterSubscriptionHealth.get_metrics()
  """
  
  use WandererKills.Observability.SubscriptionHealth,
    index_module: WandererKills.Subscriptions.CharacterIndex,
    entity_type: :character
end
