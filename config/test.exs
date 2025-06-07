import Config

# Configure the application for testing
config :wanderer_kills,
  # Disable external services in tests
  start_preloader: false,
  start_redisq: false,

  # Disable ETS supervisor in tests (managed manually)
  start_ets_supervisor: false,

  # Fast cache expiry for tests (flattened structure)
  cache_killmails_ttl: 1,
  cache_system_ttl: 1,
  cache_esi_ttl: 1,

  # Short timeouts for faster test runs
  retry_http_max_retries: 1,
  retry_http_base_delay: 100,
  retry_redisq_max_retries: 1,
  retry_redisq_base_delay: 100,

  # Fast intervals for tests
  redisq_fast_interval_ms: 100,
  redisq_idle_interval_ms: 100,
  redisq_task_timeout_ms: 1_000,

  # Short timeouts for other services
  enricher_task_timeout_ms: 1_000,
  parser_summary_interval_ms: 100,
  killmail_store_gc_interval_ms: 100,

  # Mock clients for testing
  http_client: WandererKills.Http.Client.Mock,
  zkb_client: WandererKills.Zkb.Client.Mock,
  esi_client: WandererKills.ESI.Client.Mock,

  # Use test cache names
  killmails_cache_name: :wanderer_test_killmails_cache,
  system_cache_name: :wanderer_test_system_cache,
  esi_cache_name: :wanderer_test_esi_cache,

  # Disable telemetry in tests
  telemetry_enabled_metrics: [],
  telemetry_sampling_rate: 0.0

# ESI cache configuration removed - now using Cache.Helper directly

# Configure Cachex for tests
config :cachex, :default_ttl, :timer.minutes(1)

# Configure Mox - use global mode
config :mox, global: true

# Logger configuration for tests
config :logger, level: :warning
