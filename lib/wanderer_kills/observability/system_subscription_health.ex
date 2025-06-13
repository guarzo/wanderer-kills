defmodule WandererKills.Observability.SystemSubscriptionHealth do
  @moduledoc """
  Health check implementation for system subscription components.
  
  This module provides comprehensive health monitoring for the system
  subscription system using the unified SubscriptionHealth implementation.
  It monitors the SystemIndex performance, memory usage, and subscription
  volume with system-specific thresholds and test patterns.
  
  ## Health Checks
  
  - **Index Availability**: Verifies SystemIndex GenServer is responding
  - **Performance**: Tests system lookup performance (target < 1ms)
  - **Memory Usage**: Monitors ETS table memory consumption  
  - **Subscription Volume**: Tracks system subscription counts
  
  ## Integration
  
  Integrates with ApplicationHealth to provide system subscription
  health status as part of overall application monitoring.
  
  ## Usage
  
      # Check health status
      health = SystemSubscriptionHealth.check_health()
      
      # Get detailed metrics
      metrics = SystemSubscriptionHealth.get_metrics()
  """
  
  use WandererKills.Observability.SubscriptionHealth,
    index_module: WandererKills.Subscriptions.SystemIndex,
    entity_type: :system
end
