import Config

config :wanderer_kills,
  # Cache configuration
  cache_killmails_ttl: 3600,
  cache_system_ttl: 1800,
  cache_esi_ttl: 3600,
  cache_esi_killmail_ttl: 86_400,
  cache_system_recent_fetch_threshold: 5,

  # Parser configuration
  parser_cutoff_seconds: 3_600,
  parser_summary_interval_ms: 60_000,

  # Enricher configuration
  enricher_max_concurrency: 10,
  enricher_task_timeout_ms: 30_000,
  enricher_min_attackers_for_parallel: 3,

  # Batch processing configuration
  concurrency_batch_size: 100,

  # Service URLs
  esi_base_url: "https://esi.evetech.net/latest",
  zkb_base_url: "https://zkillboard.com/api",

  # HTTP client configuration
  http_client: WandererKills.Http.Client,

  # Storage configuration
  storage: [
    enable_event_streaming: true
  ],

  # Request timeout configuration (missing from original config)
  esi_request_timeout_ms: 30_000,
  zkb_request_timeout_ms: 15_000,
  http_request_timeout_ms: 10_000,
  default_request_timeout_ms: 10_000,

  # Batch concurrency configuration
  esi_batch_concurrency: 10,
  zkb_batch_concurrency: 5,
  default_batch_concurrency: 5,

  # Retry configuration
  retry_http_max_retries: 3,
  retry_http_base_delay: 1000,
  retry_http_max_delay: 30_000,
  retry_redisq_max_retries: 5,
  retry_redisq_base_delay: 500,

  # RedisQ stream configuration
  redisq_base_url: "https://zkillredisq.stream/listen.php",
  redisq_fast_interval_ms: 1_000,
  redisq_idle_interval_ms: 5_000,
  redisq_initial_backoff_ms: 1_000,
  redisq_max_backoff_ms: 30_000,
  redisq_backoff_factor: 2,
  redisq_task_timeout_ms: 10_000,

  # Killmail store configuration
  killmail_store_gc_interval_ms: 60_000,
  killmail_store_max_events_per_system: 10_000,

  # Telemetry configuration
  telemetry_enabled_metrics: [:cache, :api, :circuit, :event],
  telemetry_sampling_rate: 1.0,
  # 7 days in seconds
  telemetry_retention_period: 604_800,

  # Service startup configuration
  start_preloader: true,
  start_redisq: true,

  # WebSocket configuration
  websocket_degraded_threshold: 1000

# Configure the Phoenix endpoint
config :wanderer_kills, WandererKillsWeb.Endpoint,
  http: [port: 4004, ip: {0, 0, 0, 0}],
  server: true,
  pubsub_server: WandererKills.PubSub

# Cachex default configuration
config :cachex, :default_ttl, :timer.hours(24)

# Configure the logger
config :logger,
  level: :info,
  format: "$time $metadata[$level] $message\n",
  metadata: :all,
  backends: [:console]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: :all

# Import environment specific config
import_config "#{config_env()}.exs"

# Phoenix PubSub configuration
config :wanderer_kills, WandererKills.PubSub, adapter: Phoenix.PubSub.PG
