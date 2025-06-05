import Config

# Configure the application for testing
config :wanderer_kills,
  # Use mock HTTP client for testing
  http_client: WandererKills.MockHttpClient,
  # Use test cache names
  killmails_cache_name: :wanderer_test_killmails_cache,
  system_cache_name: :wanderer_test_system_cache,
  esi_cache_name: :wanderer_test_esi_cache,
  # Disable preloader and RedisQ in tests
  start_preloader: false

# Configure ESI cache to use mock HTTP client
config :wanderer_kills, WandererKills.Cache.Specialized.EsiCache,
  http_client: WandererKills.MockHttpClient

# Configure Cachex for tests
config :cachex, :default_ttl, :timer.minutes(1)

# Configure Mox - use global mode
config :mox, global: true
