import Config

# Load shared logger metadata configuration
Code.require_file("logger_metadata.exs", __DIR__)

# Override logger metadata for development to exclude verbose fields (pid, application, mfa)
config :logger, :console, metadata: LoggerMetadata.dev()

# Enable WebSocket transport logging for development debugging
config :wanderer_kills, WandererKillsWeb.Endpoint,
  http: [port: 4004, ip: {0, 0, 0, 0}],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/wanderer_kills_web/(live|views)/.*(ex)$",
      ~r"lib/wanderer_kills_web/templates/.*(eex)$"
    ]
  ]

# Enable more detailed WebSocket logging for debugging
config :phoenix, :socket_drainer_timeout, 5_000

# Override socket configuration for development debugging
config :wanderer_kills, WandererKillsWeb.Endpoint, socket_drainer_timeout: 5_000

# Enable detailed logging for Phoenix and transport layers
config :logger, level: :info

# Enable Phoenix debug logs
config :phoenix, :logger, true
config :phoenix, :stacktrace_depth, 20
