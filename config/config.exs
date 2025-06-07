import Config

config :wanderer_kills,
  port: String.to_integer(System.get_env("PORT") || "4004"),

  # Flattened cache configuration (was nested in cache: %{})
  cache_killmails_ttl: 3600,
  cache_system_ttl: 1800,
  cache_esi_ttl: 3600,

  # System cache thresholds
  cache_system_recent_fetch_threshold: 5,

  # Flattened parser configuration (was nested in parser: %{})
  parser_cutoff_seconds: 3_600,
  parser_summary_interval_ms: 60_000,

  # Flattened enricher configuration (was nested in enricher: %{})
  enricher_max_concurrency: 10,
  enricher_task_timeout_ms: 30_000,
  enricher_min_attackers_for_parallel: 3,

  # Flattened concurrency configuration (was nested in concurrency: %{})
  concurrency_batch_size: 100,

  # Flattened ESI configuration (was nested in esi: %{})
  esi_base_url: "https://esi.evetech.net/latest",

  # Flattened zKillboard configuration (was nested in zkb: %{})
  zkb_base_url: "https://zkillboard.com/api",

  # HTTP client configuration
  http_client: WandererKills.Http.Client,

  # Flattened retry configuration (was nested in retry: %{})
  retry_http_max_retries: 3,
  retry_http_base_delay: 1000,
  retry_redisq_max_retries: 5,
  retry_redisq_base_delay: 500,

  # Flattened RedisQ stream configuration (was nested in redisq: %{})
  redisq_base_url: "https://zkillredisq.stream/listen.php",
  redisq_fast_interval_ms: 1_000,
  redisq_idle_interval_ms: 5_000,
  redisq_initial_backoff_ms: 1_000,
  redisq_max_backoff_ms: 30_000,
  redisq_backoff_factor: 2,
  redisq_task_timeout_ms: 10_000,

  # Flattened killmail store configuration (was nested in killmail_store: %{})
  killmail_store_gc_interval_ms: 60_000,
  killmail_store_max_events_per_system: 10_000,

  # Flattened HTTP status code mappings (was nested in http_status_codes: %{})
  http_status_success: 200..299,
  http_status_not_found: 404,
  http_status_rate_limited: 429,
  http_status_retryable: [408, 429, 500, 502, 503, 504],
  http_status_fatal: [
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
  ],

  # Flattened circuit breaker configuration (was nested in circuit_breaker: %{})
  circuit_breaker_zkb_failure_threshold: 10,
  circuit_breaker_esi_failure_threshold: 5,

  # Flattened telemetry configuration (was nested in telemetry: %{})
  telemetry_enabled_metrics: [:cache, :api, :circuit, :event],
  telemetry_sampling_rate: 1.0,
  # 7 days in seconds
  telemetry_retention_period: 604_800,

  # Add configuration guards for services (for test environment)
  start_preloader: true,
  start_redisq: true

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
    :event_count,
    :opts,
    :response,
    :size,
    :format,
    :percentage,
    :description,
    :recommendation,
    :data_source,
    :total_killmails_analyzed,
    :format_distribution,
    :purpose,
    :sample_index,
    :structure,
    :has_full_data,
    :needs_esi_fetch,
    :raw_keys,
    :raw_structure,
    :byte_size,
    :data_type,
    :killmail_keys,
    :killmail_sample,
    :available_keys,
    :has_solar_system_id,
    :has_victim,
    :has_attackers,
    :has_killmail_id,
    :has_kill_time,
    :has_solar_system_id,
    :has_victim,
    :has_attackers,
    :has_killmail_id,
    :has_kill_time,
    :kill_count,
    :raw_count,
    :parsed_count,
    :parser_type,
    :cached_count,
    :stats,
    :total_calls,
    :victim_ship_type_id,
    :attacker_count,
    :has_zkb_data,
    :enriched_count,
    :processed_count,
    :sample_structure,
    :request_type,
    :required_fields,
    :missing_fields,
    :has_zkb,
    :total_tables,
    :successful_tables,
    :name,
    :table_count,
    :enriched_count,
    :cutoff_time,
    :enrich,
    :total_systems,
    :successful_systems,
    :missing_tables,
    :killmail_hash,
    :error_count,
    :success_count,
    :group_ids,
    :total_groups,
    :table,
    :expired_count,
    :type_count,
    :type,
    :entry
  ]

# Import environment specific config
import_config "#{config_env()}.exs"

# Phoenix PubSub configuration
config :wanderer_kills, WandererKills.PubSub, adapter: Phoenix.PubSub.PG
