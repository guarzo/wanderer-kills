import Config

# For production, configure the endpoint to load runtime configuration
config :wanderer_kills, WandererKillsWeb.Endpoint,
  http: [port: {:system, "PORT", 4004}],
  url: [host: System.get_env("HOST", "localhost"), port: 443, scheme: "https"],
  check_origin: false,
  server: true

# Configure logger for production
config :logger,
  level: :info,
  format: "$time $metadata[$level] $message\n"

# Runtime configuration should be loaded from runtime.exs
