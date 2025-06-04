import Config

# Configure the logger for development
config :logger,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: :all
