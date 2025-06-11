import Config

# Runtime configuration that can read environment variables
# This replaces the deprecated init/2 callback in the endpoint

# Configure the port for the Phoenix endpoint
port = String.to_integer(System.get_env("PORT") || "4004")

config :wanderer_kills, WandererKillsWeb.Endpoint,
  http: [port: port]

# Also configure the main application port for consistency
config :wanderer_kills, port: port
