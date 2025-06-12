defmodule WandererKills.Config do
  @moduledoc """
  Centralized configuration access for WandererKills.

  This module provides access to the application's nested configuration structure
  with sensible defaults. It supports both the new nested format and legacy
  flat configuration for backward compatibility.

  ## Configuration Structure

  The configuration is organized into logical groups:
  - `:cache` - Caching configuration (TTLs, thresholds)
  - `:esi` - ESI API configuration (URL, timeouts, concurrency)
  - `:http` - HTTP client configuration (timeouts, retries)
  - `:zkb` - ZKillboard configuration (URL, timeouts)
  - `:redisq` - RedisQ streaming configuration
  - `:parser` - Killmail parsing configuration
  - `:enricher` - Data enrichment configuration
  - `:batch` - Batch processing configuration
  - `:storage` - Storage and event streaming configuration
  - `:monitoring` - Monitoring intervals
  - `:telemetry` - Telemetry configuration
  - `:websocket` - WebSocket configuration
  - `:services` - Service startup flags
  - `:ship_types` - Ship type validation configuration

  ## Usage

      # Access nested configuration
      Config.get([:cache, :killmails_ttl], 3600)
      
      # Access configuration group
      Config.cache()
      
      # Legacy flat access (for backward compatibility)
      Config.get(:cache_killmails_ttl, 3600)
  """

  @app_name :wanderer_kills

  # Default values for all configuration options
  @defaults %{
    cache: %{
      killmails_ttl: 3600,
      system_ttl: 1800,
      esi_ttl: 3600,
      esi_killmail_ttl: 86_400,
      system_recent_fetch_threshold: 5
    },
    esi: %{
      base_url: "https://esi.evetech.net/latest",
      request_timeout_ms: 30_000,
      batch_concurrency: 10
    },
    http: %{
      client: WandererKills.Http.Client,
      request_timeout_ms: 10_000,
      default_timeout_ms: 10_000,
      retry: %{
        max_retries: 3,
        base_delay: 1000,
        max_delay: 30_000
      }
    },
    zkb: %{
      base_url: "https://zkillboard.com/api",
      request_timeout_ms: 15_000,
      batch_concurrency: 5
    },
    redisq: %{
      base_url: "https://zkillredisq.stream/listen.php",
      fast_interval_ms: 1_000,
      idle_interval_ms: 5_000,
      initial_backoff_ms: 1_000,
      max_backoff_ms: 30_000,
      backoff_factor: 2,
      task_timeout_ms: 10_000,
      retry: %{
        max_retries: 5,
        base_delay: 500
      }
    },
    parser: %{
      cutoff_seconds: 3_600,
      summary_interval_ms: 60_000
    },
    enricher: %{
      max_concurrency: 10,
      task_timeout_ms: 30_000,
      min_attackers_for_parallel: 3
    },
    batch: %{
      concurrency_size: 100,
      default_concurrency: 5
    },
    storage: %{
      enable_event_streaming: true,
      gc_interval_ms: 60_000,
      max_events_per_system: 10_000
    },
    monitoring: %{
      status_interval_ms: 300_000,
      health_check_interval_ms: 60_000
    },
    telemetry: %{
      enabled_metrics: [:cache, :api, :circuit, :event],
      sampling_rate: 1.0,
      retention_period: 604_800
    },
    websocket: %{
      degraded_threshold: 1000
    },
    services: %{
      start_preloader: true,
      start_redisq: true
    }
  }

  @doc """
  Get a configuration value with optional default.

  Supports both nested and flat key formats for backward compatibility.

  ## Examples
      
      # Nested access
      Config.get([:cache, :killmails_ttl])
      
      # Legacy flat access
      Config.get(:cache_killmails_ttl)
      
      # With custom default
      Config.get([:cache, :custom_ttl], 7200)
  """
  def get(key, default \\ nil)

  # Handle nested key access
  def get([group | path], default) when is_atom(group) and is_list(path) do
    group_config = Application.get_env(@app_name, group, get_in(@defaults, [group]))

    case get_in(group_config, path) do
      nil -> default
      value -> value
    end
  end

  # Handle legacy flat key access by converting to nested
  def get(key, default) when is_atom(key) do
    # First try direct access (for non-nested configs)
    case Application.get_env(@app_name, key) do
      nil ->
        # Try to convert flat key to nested key
        case flat_to_nested_key(key) do
          {group, nested_path} -> get([group | nested_path], default)
          nil -> default
        end

      value ->
        value
    end
  end

  @doc """
  Get all configuration for the application.
  """
  def all do
    Application.get_all_env(@app_name)
  end

  # Configuration group accessors

  @doc "Get cache configuration"
  def cache do
    get_group(:cache)
  end

  @doc "Get ESI configuration"
  def esi do
    get_group(:esi)
  end

  @doc "Get HTTP configuration"
  def http do
    get_group(:http)
  end

  @doc "Get ZKillboard configuration"
  def zkb do
    get_group(:zkb)
  end

  @doc "Get RedisQ configuration"
  def redisq do
    get_group(:redisq)
  end

  @doc "Get parser configuration"
  def parser do
    get_group(:parser)
  end

  @doc "Get enricher configuration"
  def enricher do
    get_group(:enricher)
  end

  @doc "Get batch processing configuration"
  def batch do
    get_group(:batch)
  end

  @doc "Get storage configuration"
  def storage do
    get_group(:storage)
  end

  @doc "Get monitoring configuration"
  def monitoring do
    get_group(:monitoring)
  end

  @doc "Get telemetry configuration"
  def telemetry do
    get_group(:telemetry)
  end

  @doc "Get WebSocket configuration"
  def websocket do
    get_group(:websocket)
  end

  @doc "Get services configuration"
  def services do
    get_group(:services)
  end

  @doc "Get ship types configuration"
  def ship_types do
    Application.get_env(@app_name, :ship_types, %{})
  end

  # Legacy compatibility functions

  @doc "Get retry configuration (legacy)"
  def retry do
    %{
      http_max_retries: get([:http, :retry, :max_retries]),
      http_base_delay: get([:http, :retry, :base_delay]),
      http_max_delay: get([:http, :retry, :max_delay]),
      redisq_max_retries: get([:redisq, :retry, :max_retries]),
      redisq_base_delay: get([:redisq, :retry, :base_delay])
    }
  end

  @doc "Get application configuration (legacy)"
  def app do
    %{
      port: get_endpoint_port(),
      http_client: get([:http, :client]),
      zkb_client: get(:zkb_client, WandererKills.Killmails.ZkbClient),
      start_redisq: get([:services, :start_redisq])
    }
  end

  @doc "Get killmail store configuration (legacy)"
  def killmail_store do
    %{
      gc_interval_ms: get([:storage, :gc_interval_ms]),
      max_events_per_system: get([:storage, :max_events_per_system])
    }
  end

  @doc "Get all service URLs"
  def service_urls do
    %{
      esi_base_url: get([:esi, :base_url]),
      zkb_base_url: get([:zkb, :base_url]),
      redisq_base_url: get([:redisq, :base_url]),
      eve_db_dump_url: get(:eve_db_dump_url, "https://www.fuzzwork.co.uk/dump/latest")
    }
  end

  @doc "Get all timeout values"
  def timeouts do
    %{
      esi_request_ms: get([:esi, :request_timeout_ms]),
      zkb_request_ms: get([:zkb, :request_timeout_ms]),
      http_request_ms: get([:http, :request_timeout_ms]),
      default_request_ms: get([:http, :default_timeout_ms]),
      health_check_ms: get(:health_check_timeout_ms, 10_000),
      health_check_cache_ms: get(:health_check_cache_timeout_ms, 5_000),
      gen_server_call_ms: gen_server_call_timeout()
    }
  end

  @doc "Get metadata configuration"
  def metadata do
    %{
      user_agent:
        get(
          :user_agent,
          "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"
        ),
      github_url: get(:github_url, "https://github.com/wanderer-industries/wanderer-kills"),
      contact_email: get(:contact_email, "wanderer-kills@proton.me")
    }
  end

  # Constants that shouldn't change at runtime
  def gen_server_call_timeout, do: 5_000
  def max_killmail_id, do: 999_999_999_999
  def max_system_id, do: 34_999_999
  def max_character_id, do: 2_129_999_999
  def max_subscribed_systems, do: 100

  # Validation helper
  def validation(:max_subscribed_systems), do: max_subscribed_systems()
  def validation(:max_killmail_id), do: max_killmail_id()
  def validation(:max_system_id), do: max_system_id()
  def validation(:max_character_id), do: max_character_id()

  # Compatibility helpers
  def start_redisq?, do: get([:services, :start_redisq])

  # Private functions

  defp get_group(group) when is_atom(group) do
    config = Application.get_env(@app_name, group, Map.get(@defaults, group, %{}))

    # Convert keyword list to map if necessary
    case config do
      config when is_list(config) ->
        Enum.into(config, %{})

      config when is_map(config) ->
        config

      _ ->
        require Logger
        Logger.debug("Unknown config type for group #{inspect(group)}: #{inspect(config)}")
        %{}
    end
  end

  defp get_endpoint_port do
    case WandererKillsWeb.Endpoint.config(:http) do
      nil -> 4004
      http_config when is_list(http_config) -> Keyword.get(http_config, :port, 4004)
      _ -> 4004
    end
  end

  # Convert flat keys to nested keys for backward compatibility
  defp flat_to_nested_key(key) do
    key_string = Atom.to_string(key)

    cond do
      String.starts_with?(key_string, "retry_http_") ->
        rest = String.trim_leading(key_string, "retry_http_")
        {:http, [:retry, safe_to_existing_atom(rest)]}

      String.starts_with?(key_string, "retry_redisq_") ->
        rest = String.trim_leading(key_string, "retry_redisq_")
        {:redisq, [:retry, safe_to_existing_atom(rest)]}

      String.starts_with?(key_string, "start_") ->
        {:services, [safe_to_existing_atom(key_string)]}

      true ->
        simple_prefix_mapping(key_string)
    end
  end

  defp simple_prefix_mapping(key_string) do
    prefix_map = %{
      "cache_" => :cache,
      "esi_" => :esi,
      "zkb_" => :zkb,
      "redisq_" => :redisq,
      "parser_" => :parser,
      "enricher_" => :enricher,
      "telemetry_" => :telemetry,
      "websocket_" => :websocket
    }

    Enum.find_value(prefix_map, nil, fn {prefix, group} ->
      if String.starts_with?(key_string, prefix) do
        rest = String.trim_leading(key_string, prefix)
        {group, [safe_to_existing_atom(rest)]}
      end
    end)
  end

  defp safe_to_existing_atom(string) do
    try do
      String.to_existing_atom(string)
    rescue
      ArgumentError -> string
    end
  end
end
