import Config

# Runtime configuration that can read environment variables
# This replaces the deprecated init/2 callback in the endpoint

# Get current environment
env = config_env()

# Get secret key base with proper validation
secret_key_base =
  case {System.get_env("SECRET_KEY_BASE"), env} do
    {nil, :prod} ->
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

    {nil, _} ->
      # Development/test fallback
      "wanderer_kills_secret_key_base_development_only_do_not_use_in_production"

    {key, :prod} when byte_size(key) < 64 ->
      raise """
      environment variable SECRET_KEY_BASE is too short.
      You can generate one by calling: mix phx.gen.secret
      """

    {key, _} ->
      key
  end

# Get LiveView signing salt with proper validation
live_view_salt =
  case {System.get_env("LIVE_VIEW_SALT"), env} do
    {nil, :prod} ->
      raise """
      environment variable LIVE_VIEW_SALT is missing.
      You can generate one by calling: mix phx.gen.secret 32
      """

    {nil, _} ->
      # Development/test fallback
      "wanderer_kills_live_view_salt_dev"

    {salt, :prod} when byte_size(salt) < 32 ->
      raise """
      environment variable LIVE_VIEW_SALT is too short.
      You can generate one by calling: mix phx.gen.secret 32
      """

    {salt, _} ->
      salt
  end

# Configure the port for the Phoenix endpoint
port = String.to_integer(System.get_env("PORT") || "4004")

config :wanderer_kills, WandererKillsWeb.Endpoint,
  http: [port: port],
  secret_key_base: secret_key_base,
  live_view: [signing_salt: live_view_salt]

# Also configure the main application port for consistency
config :wanderer_kills, port: port
