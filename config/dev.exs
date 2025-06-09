import Config

# Override logger metadata for development to exclude verbose fields (pid, application, mfa)
config :logger, :console,
  metadata: [
    :request_id,
    :file,
    :line,
    :system_id,
    :killmail_id,
    :operation,
    :step,
    :status,
    :error,
    :duration,
    :source,
    :reason,
    :url,
    :response_time,
    :method,
    :service,
    :endpoint,
    :cache,
    :cache_key,
    :cache_type,
    :ttl,
    :killmail_count,
    :count,
    :result,
    :data_source,
    :kills_processed,
    :kills_older,
    :kills_skipped,
    :legacy_kills,
    :no_kills_polls,
    :errors,
    :active_systems,
    :total_polls
  ]

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
