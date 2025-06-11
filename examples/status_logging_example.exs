defmodule StatusLoggingExample do
  @moduledoc """
  Example demonstrating the enhanced 5-minute status logging functionality.
  
  This shows how the WebSocketStats module now logs comprehensive system status
  every 5 minutes, including:
  - WebSocket activity metrics
  - RedisQ processing statistics
  - Cache performance metrics
  - Storage metrics
  """
  
  def example_output do
    """
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    📊 WANDERER KILLS STATUS REPORT (5-minute summary)
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    🌐 WEBSOCKET ACTIVITY:
       Active Connections: 15
       Total Connected: 45 | Disconnected: 30
       Active Subscriptions: 12 (covering 87 systems)
       Avg Systems/Subscription: 7.3
    
    📤 KILL DELIVERY:
       Total Kills Sent: 1234 (Realtime: 1150, Preload: 84)
       Delivery Rate: 4.1 kills/minute
       Connection Rate: 0.15 connections/minute
    
    🔄 REDISQ ACTIVITY:
       Kills Processed: 327
       Older Kills: 12 | Skipped: 5
       Active Systems: 45
       Total Polls: 1502 | Errors: 3
    
    💾 CACHE PERFORMANCE:
       Hit Rate: 87.5%
       Total Operations: 5420 (Hits: 4742, Misses: 678)
       Cache Size: 2156 entries
       Evictions: 23
    
    📦 STORAGE METRICS:
       Total Killmails: 15234
       Unique Systems: 234
       Avg Killmails/System: 65.1
    
    ⏰ Report Generated: 2024-01-15T14:30:00Z
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """
  end
  
  def configuration do
    """
    The enhanced status logging is automatically enabled with WebSocketStats.
    
    The logging interval is configured to 5 minutes:
    @stats_summary_interval :timer.minutes(5)
    
    To manually trigger a status report:
    WandererKills.Observability.WebSocketStats.get_stats()
    
    The report includes data from:
    1. WebSocketStats - Connection and delivery metrics
    2. RedisQ - Killmail processing statistics  
    3. Cachex - Cache performance metrics
    4. ETS Store - Storage utilization metrics
    """
  end
  
  def metadata_fields do
    """
    The following metadata fields are included for log filtering/searching:
    
    - websocket_active_connections
    - websocket_kills_sent_total
    - websocket_kills_sent_realtime
    - websocket_kills_sent_preload
    - websocket_active_subscriptions
    - websocket_total_systems
    - websocket_kills_per_minute
    - websocket_connections_per_minute
    - redisq_kills_processed
    - redisq_active_systems
    - cache_hit_rate
    - cache_total_size
    - store_total_killmails
    - store_unique_systems
    """
  end
end