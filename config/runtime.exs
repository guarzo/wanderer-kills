import Config

# Runtime configuration that can read environment variables
# This replaces the deprecated init/2 callback in the endpoint

# Configure the port for the Phoenix endpoint
port_str = System.get_env("PORT") || "4004"

port =
  case Integer.parse(port_str) do
    {port, ""} when port > 0 and port <= 65535 ->
      port

    _ ->
      raise """
      Invalid PORT environment variable: #{inspect(port_str)}
      PORT must be a valid integer between 1 and 65535
      """
  end

config :wanderer_kills, WandererKillsWeb.Endpoint, http: [port: port]

# Also configure the main application port for consistency
config :wanderer_kills, port: port
