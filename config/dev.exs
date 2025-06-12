import Config

# Development environment configuration
# Most settings are now in runtime.exs for better environment variable support

# Configure Phoenix endpoint for development
config :wanderer_kills, WandererKillsWeb.Endpoint, http: [port: 4004, ip: {0, 0, 0, 0}]

# Enable detailed logging for development
config :logger, level: :debug
