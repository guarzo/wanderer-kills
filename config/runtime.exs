import Config

# Runtime configuration that can read environment variables
# This replaces the deprecated init/2 callback in the endpoint

# Configure the port for the Phoenix endpoint
port = String.to_integer(System.get_env("PORT") || "4004")

config :wanderer_kills, WandererKillsWeb.Endpoint,
  http: [port: port],
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") || "wanderer_kills_secret_key_base_development_only"

# Also configure the main application port for consistency
config :wanderer_kills, port: port
