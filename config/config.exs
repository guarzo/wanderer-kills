import Config

config :wanderer_kills,
  port: String.to_integer(System.get_env("PORT") || "4004"),

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

  # Request timeout configuration (missing from original config)
  esi_request_timeout_ms: 30_000,
  zkb_request_timeout_ms: 15_000,
  http_request_timeout_ms: 10_000,
  default_request_timeout_ms: 10_000,

  # Batch concurrency configuration (missing from original config)
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
    # Standard Elixir metadata
    :request_id,
    :application,
    :module,
    :function,
    :line,

    # Core application metadata
    :system_id,
    :killmail_id,
    :operation,
    :step,
    :status,
    :error,
    :duration,
    :source,
    :reason,

    # HTTP and API metadata
    :url,
    :response_time,
    :method,
    :service,
    :endpoint,

    # EVE Online entity metadata
    :character_id,
    :corporation_id,
    :alliance_id,
    :type_id,
    :solar_system_id,
    :ship_type_id,

    # Cache metadata
    :cache,
    :cache_key,
    :cache_type,
    :ttl,

    # Processing metadata
    :killmail_count,
    :count,
    :result,
    :data_source,

    # Retry and timeout metadata
    :attempt,
    :max_attempts,
    :remaining_attempts,
    :delay_ms,
    :timeout,
    :request_type,
    :raw_count,
    :parsed_count,
    :enriched_count,
    :since_hours,
    :provided_id,
    :types,
    :groups,
    :file,
    :path,
    :pass_type,
    :hours,
    :limit,
    :max_concurrency,
    :purpose,
    :format,
    :percentage,
    :description,
    :unit,
    :value,
    :count,
    :total,
    :processed,
    :skipped,
    :error,
    :total_killmails_analyzed,
    :format_distribution,
    :system_distribution,
    :ship_distribution,
    :character_distribution,
    :corporation_distribution,
    :alliance_distribution,
    :ship_type_distribution,
    :purpose,
    :sample_index,
    :sample_size,
    :sample_type,
    :sample_value,
    :sample_unit,
    :sample_value,
    :sample_structure,
    :data_type,
    :raw_keys,
    :has_full_data,
    :needs_esi_fetch,
    :byte_size,
    :tasks,
    :group_ids,
    :error_count,
    :total_groups,
    :success_count,
    :type_count,
    :cutoff_time,
    :killmail_sample,
    :required_fields,
    :missing_fields,
    :available_keys,
    :killmail_sample,
    :raw_structure,
    :parsed_structure,
    :enriched_structure,
    :killmail_id,
    :system_id,
    :ship_type_id,
    :character_id,
    :killmail_keys,
    :kill_count,
    :hash,
    :has_solar_system_id,
    :has_kill_count,
    :has_hash,
    :has_killmail_id,
    :has_system_id,
    :has_ship_type_id,
    :has_character_id,
    :has_victim,
    :has_attackers,
    :has_zkb,
    :killmail_keys,
    :parser_type,
    :killmail_hash,
    :raw_structure,
    :recommendation,
    :structure,
    :kill_time,
    :cutoff,
    :subscriber_id,
    :system_ids,
    :callback_url,
    :subscription_id,
    :status,
    :error,
    :system_count,
    :has_callback,
    :error_count,
    :success_count,
    :total_subscriptions,
    :active_subscriptions,
    :removed_count,
    :requested_systems,
    :successful_systems,
    :failed_systems,
    :total_systems,
    :system_ids,
    :callback_url,
    :subscription_id,
    :status,
    :kills_count,
    :pubsub_name,
    :pubsub_topic,
    :pubsub_message,
    :pubsub_metadata,
    :pubsub_payload,
    :pubsub_headers,
    :pubsub_timestamp,
    :total_kills,
    :filtered_kills,
    :subscriber_count,
    :total_cached_kills,
    :cache_error,
    :returned_kills,
    :unexpected_response
  ]

# Import environment specific config
import_config "#{config_env()}.exs"

# Phoenix PubSub configuration
config :wanderer_kills, WandererKills.PubSub, adapter: Phoenix.PubSub.PG
