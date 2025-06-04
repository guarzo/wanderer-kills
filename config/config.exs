import Config

config :wanderer_kills,
  port: String.to_integer(System.get_env("PORT") || "4004"),
  # Cache configuration
  cache: %{
    killmails: [name: :killmails_cache, ttl: :timer.hours(24)],
    system: [name: :system_cache, ttl: :timer.hours(1)],
    esi: [name: :esi_cache, ttl: :timer.hours(48)]
  },
  # System cache thresholds
  recent_fetch_threshold_ms: 300_000,
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
    max_concurrent: 10,
    batch_size: 50,
    timeout_ms: 30_000
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
  retry: [
    max_retries: 3,
    base_backoff: 1000,
    max_backoff: 30_000
  ],
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
    :timeout
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
