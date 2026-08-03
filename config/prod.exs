import Config

# Set environment for runtime checks
config :wanderer_kills, env: :prod

# For production, configure the endpoint to load runtime configuration
# Note: URL, port, and check_origin are now configured in runtime.exs via environment variables
#
# :debug_errors and :code_reloader must be set here rather than in runtime.exs.
# Phoenix 1.8 reads both through Application.compile_env/3 (1.7 read them from
# runtime config), so setting them at runtime aborts the release at boot with a
# compile-env mismatch. See config/dev.exs for the same note.
config :wanderer_kills, WandererKillsWeb.Endpoint,
  server: true,
  debug_errors: false,
  code_reloader: false

# Configure logger for production
config :logger, level: :info

config :logger, :default_formatter, format: "$time $metadata[$level] $message\n"

# Runtime configuration should be loaded from runtime.exs
