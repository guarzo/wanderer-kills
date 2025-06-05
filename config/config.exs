import Config

config :wanderer_kills,
  port: String.to_integer(System.get_env("PORT") || "4004"),
  # Cache configuration
  cache: %{
    killmails: %{ttl: 3600},
    system: %{ttl: 1800},
    esi: %{ttl: 3600}
  },
  # System cache thresholds
  cache_system_recent_fetch_threshold: 5,
  # Parser configuration
  parser: %{
    cutoff_seconds: 3_600,
    summary_interval_ms: 60_000
  },
  # Enricher configuration
  enricher: %{
    max_concurrency: 10,
    task_timeout_ms: 30_000,
    min_attackers_for_parallel: 3
  },
  # Concurrency configuration for batch operations
  concurrency: %{
    batch_size: 100
  },
  # ESI API configuration
  esi: %{
    base_url: "https://esi.evetech.net/latest"
  },
  # zKillboard API configuration
  zkb: %{
    base_url: "https://zkillboard.com/api"
  },
  # HTTP client configuration
  http_client: WandererKills.Http.Client,
  # Retry configuration
  retry: %{
    http: %{max_retries: 3, base_delay: 1000},
    redisq: %{max_retries: 5, base_delay: 500}
  },
  # RedisQ stream configuration
  redisq: %{
    base_url: "https://zkillredisq.stream/listen.php",
    fast_interval_ms: 1_000,
    idle_interval_ms: 5_000,
    initial_backoff_ms: 1_000,
    max_backoff_ms: 30_000,
    backoff_factor: 2,
    task_timeout_ms: 10_000
  },
  # Killmail store configuration
  killmail_store: %{
    # How often to run garbage collection to remove old events (in milliseconds)
    gc_interval_ms: 60_000,
    # Maximum number of events to keep per system before older ones are removed
    max_events_per_system: 10_000
  },
  # HTTP status code mappings
  http_status_codes: %{
    success: 200..299,
    not_found: 404,
    rate_limited: 429,
    retryable: [408, 429, 500, 502, 503, 504],
    fatal: [
      400,
      401,
      403,
      405,
      406,
      407,
      409,
      410,
      411,
      412,
      413,
      414,
      415,
      416,
      417,
      418,
      421,
      422,
      423,
      424,
      426,
      428,
      431,
      451
    ]
  },
  # Circuit breaker configuration
  circuit_breaker: %{
    zkb: %{failure_threshold: 10},
    esi: %{failure_threshold: 5}
  },
  # Telemetry configuration
  telemetry: %{
    # Enable/disable specific metric types
    enabled_metrics: [
      :cache,
      :api,
      :circuit,
      :event
    ],
    # Sampling rate for metrics (1.0 = 100%)
    sampling_rate: 1.0,
    # Metric retention period in milliseconds
    # 7 days in seconds
    retention_period: 604_800
  }

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
  metadata: [
    :request_id,
    :application,
    :module,
    :function,
    :line,
    # Application-specific metadata
    :system_id,
    :killmail_id,
    :operation,
    :step,
    :status,
    :error,
    :killmail_count,
    :provided_id,
    :cache_key,
    :duration,
    :source,
    :reason,
    :attempt,
    :url,
    :response_time,
    :character_id,
    :corporation_id,
    :alliance_id,
    :type_id,
    :cache_type,
    :id,
    :limit,
    :since_hours,
    :force,
    :max_attempts,
    :remaining_attempts,
    :delay_ms,
    :message,
    :timestamp,
    :system_count,
    :stat,
    :new_value,
    :state,
    :hash,
    :kill_time,
    :cutoff,
    :solar_system_id,
    :solar_system_name,
    :ship_type_id,
    :options,
    :failed_count,
    :failed_ids,
    :count,
    :result,
    :kind,
    :duration_ms,
    :file,
    :path,
    :value,
    :ttl,
    :default_ttl,
    :cache_value,
    :from,
    :max_concurrency,
    :timeout,
    :endpoint,
    :client_id,
    :systems,
    :system_ids,
    :event_id,
    :killmail_id,
    :killmail,
    :killmail_count,
    :service,
    :method,
    :cache,
    :key,
    :client_id,
    :event_count
  ]

# Import environment specific config
import_config "#{config_env()}.exs"

# Phoenix PubSub configuration
config :wanderer_kills, WandererKills.PubSub, adapter: Phoenix.PubSub.PG
