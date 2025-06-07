import Config

# Configure the logger for development
config :logger,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: :all

# Console backend (existing behavior)
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: :all

# File backend for debugging
config :logger, :file,
  path: "/app/logs/wanderer_kills_debug.log",
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: :all
