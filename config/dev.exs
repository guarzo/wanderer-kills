import Config

# Development environment configuration
# Most settings are now in runtime.exs for better environment variable support

# Set environment for runtime checks
config :wanderer_kills, env: :dev

# Configure Phoenix endpoint for development
#
# :debug_errors and :code_reloader must be set here rather than in runtime.exs.
# Phoenix 1.8 reads both through Application.compile_env/3 (1.7 read them from
# runtime config), so setting them at runtime aborts boot with a compile-env
# mismatch. Everything else stays in runtime.exs.
config :wanderer_kills, WandererKillsWeb.Endpoint,
  http: [port: 4004, ip: {0, 0, 0, 0}],
  debug_errors: true,
  code_reloader: true

# Enable detailed logging for development
config :logger, level: :info
