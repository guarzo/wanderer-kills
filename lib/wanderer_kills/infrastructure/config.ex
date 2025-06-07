defmodule WandererKills.Infrastructure.Config do
  @moduledoc """
  Centralized configuration management for WandererKills.

  This module provides a unified interface for all application configuration,
  including runtime settings, constants, and environment-specific values.

  ## Configuration Groups

  - **Cache**: TTL settings and cache behavior
  - **Retry**: Retry policies and backoff strategies
  - **Batch**: Concurrency and batch processing settings
  - **Timeouts**: Request timeout configurations
  - **HTTP Status**: Status code handling rules
  - **Services**: External service URLs
  - **RedisQ**: Queue processing configuration
  - **Parser**: Killmail parsing settings
  - **Enricher**: Data enrichment configuration
  - **Killmail Store**: Storage and GC settings
  - **Telemetry**: Metrics and monitoring configuration
  - **App**: Application-level settings
  - **Constants**: Core application constants

  ## Usage

  ```elixir
  # Get specific configuration groups
  cache_config = Config.cache()
  retry_config = Config.retry()

  # Get individual values
  timeout = Config.timeouts().esi_request_ms
  max_retries = Config.retry().http_max_retries

  # Get constants
  timeout = Config.gen_server_call_timeout()
  max_id = Config.validation(:max_killmail_id)
  ```
  """

  # ============================================================================
  # Core Constants
  # ============================================================================

  # Timeout Configuration (Use Config module for runtime-configurable timeouts)
  @gen_server_call_timeout 5_000

  # Retry Configuration (Use Config module for runtime-configurable retry settings)
  @default_base_delay 1_000
  @max_backoff_delay 60_000
  @backoff_factor 2

  # Validation Limits
  @max_killmail_id 999_999_999_999
  @max_system_id 32_000_000
  @max_character_id 999_999_999_999

  defstruct [
    # Cache settings
    cache: %{
      killmails_ttl: 3600,
      system_ttl: 1800,
      esi_ttl: 3600,
      esi_killmail_ttl: 86_400,
      recent_fetch_threshold: 5
    },
    # Retry settings
    retry: %{
      http_max_retries: 3,
      http_base_delay: 1000,
      http_max_delay: 30_000,
      redisq_max_retries: 5,
      redisq_base_delay: 500
    },
    # Batch processing settings
    batch: %{
      concurrency_esi: 10,
      concurrency_zkb: 5,
      concurrency_default: 5,
      batch_size: 100
    },
    # Request timeout settings
    timeouts: %{
      esi_request_ms: 30_000,
      zkb_request_ms: 15_000,
      http_request_ms: 10_000,
      default_request_ms: 10_000
    },
    # HTTP status codes
    http_status: %{
      success: 200..299,
      not_found: 404,
      rate_limited: 429,
      retryable: [408, 429, 500, 502, 503, 504],
      fatal: [400, 401, 403, 405]
    },
    # Service URLs
    services: %{
      esi_base_url: "https://esi.evetech.net/latest",
      zkb_base_url: "https://zkillboard.com/api",
      redisq_base_url: nil
    },
    # RedisQ specific settings
    redisq: %{
      fast_interval_ms: 1_000,
      idle_interval_ms: 5_000,
      initial_backoff_ms: 1_000,
      max_backoff_ms: 30_000,
      backoff_factor: 2,
      task_timeout_ms: 10_000
    },
    # Parser settings
    parser: %{
      cutoff_seconds: 3_600,
      summary_interval_ms: 60_000
    },
    # Enricher settings
    enricher: %{
      max_concurrency: 10,
      task_timeout_ms: 30_000,
      min_attackers_for_parallel: 3
    },
    # Killmail store settings
    killmail_store: %{
      gc_interval_ms: 60_000,
      max_events_per_system: 10_000
    },
    # Telemetry settings
    telemetry: %{
      enabled_metrics: [:cache, :api, :circuit, :event],
      sampling_rate: 1.0,
      retention_period: 604_800
    },
    # Application settings
    app: %{
      port: 4004,
      http_client: "WandererKills.Core.Http.Client",
      zkb_client: WandererKills.Zkb.Client
    }
  ]

  @type config :: %__MODULE__{}

  @doc "Gets the complete configuration struct with runtime values"
  @spec config() :: config()
  def config do
    %__MODULE__{
      cache: %{
        killmails_ttl: get_env(:cache_killmails_ttl, 3600),
        system_ttl: get_env(:cache_system_ttl, 1800),
        esi_ttl: get_env(:cache_esi_ttl, 3600),
        esi_killmail_ttl: get_env(:cache_esi_killmail_ttl, 86_400),
        recent_fetch_threshold: get_env(:cache_system_recent_fetch_threshold, 5)
      },
      retry: %{
        http_max_retries: get_env(:retry_http_max_retries, 3),
        http_base_delay: get_env(:retry_http_base_delay, 1000),
        http_max_delay: get_env(:retry_http_max_delay, 30_000),
        redisq_max_retries: get_env(:retry_redisq_max_retries, 5),
        redisq_base_delay: get_env(:retry_redisq_base_delay, 500)
      },
      batch: %{
        concurrency_esi: get_env(:esi_batch_concurrency, 10),
        concurrency_zkb: get_env(:zkb_batch_concurrency, 5),
        concurrency_default: get_env(:default_batch_concurrency, 5),
        batch_size: get_env(:concurrency_batch_size, 100)
      },
      timeouts: %{
        esi_request_ms: get_env(:esi_request_timeout_ms, 30_000),
        zkb_request_ms: get_env(:zkb_request_timeout_ms, 15_000),
        http_request_ms: get_env(:http_request_timeout_ms, 10_000),
        default_request_ms: get_env(:default_request_timeout_ms, 10_000)
      },
      http_status: %{
        success: get_env(:http_status_success, 200..299),
        not_found: get_env(:http_status_not_found, 404),
        rate_limited: get_env(:http_status_rate_limited, 429),
        retryable: get_env(:http_status_retryable, [408, 429, 500, 502, 503, 504]),
        fatal: get_env(:http_status_fatal, [400, 401, 403, 405])
      },
      services: %{
        esi_base_url: get_env(:esi_base_url, "https://esi.evetech.net/latest"),
        zkb_base_url: get_env(:zkb_base_url, "https://zkillboard.com/api"),
        redisq_base_url: get_env(:redisq_base_url, nil)
      },
      redisq: %{
        fast_interval_ms: get_env(:redisq_fast_interval_ms, 1_000),
        idle_interval_ms: get_env(:redisq_idle_interval_ms, 5_000),
        initial_backoff_ms: get_env(:redisq_initial_backoff_ms, 1_000),
        max_backoff_ms: get_env(:redisq_max_backoff_ms, 30_000),
        backoff_factor: get_env(:redisq_backoff_factor, 2),
        task_timeout_ms: get_env(:redisq_task_timeout_ms, 10_000)
      },
      parser: %{
        cutoff_seconds: get_env(:parser_cutoff_seconds, 3_600),
        summary_interval_ms: get_env(:parser_summary_interval_ms, 60_000)
      },
      enricher: %{
        max_concurrency: get_env(:enricher_max_concurrency, 10),
        task_timeout_ms: get_env(:enricher_task_timeout_ms, 30_000),
        min_attackers_for_parallel: get_env(:enricher_min_attackers_for_parallel, 3)
      },
      killmail_store: %{
        gc_interval_ms: get_env(:killmail_store_gc_interval_ms, 60_000),
        max_events_per_system: get_env(:killmail_store_max_events_per_system, 10_000)
      },
      telemetry: %{
        enabled_metrics: get_env(:telemetry_enabled_metrics, [:cache, :api, :circuit, :event]),
        sampling_rate: get_env(:telemetry_sampling_rate, 1.0),
        retention_period: get_env(:telemetry_retention_period, 604_800)
      },
      app: %{
        port: get_env(:port, 4004),
        http_client: get_env(:http_client, "WandererKills.Http.Client"),
        zkb_client: get_env(:zkb_client, WandererKills.Zkb.Client)
      }
    }
  end

  # Convenience accessors for each configuration group
  @doc "Gets cache configuration"
  @spec cache() :: map()
  def cache, do: config().cache

  @doc "Gets retry configuration"
  @spec retry() :: map()
  def retry, do: config().retry

  @doc "Gets batch processing configuration"
  @spec batch() :: map()
  def batch, do: config().batch

  @doc "Gets timeout configuration"
  @spec timeouts() :: map()
  def timeouts, do: config().timeouts

  @doc "Gets HTTP status configuration"
  @spec http_status() :: map()
  def http_status, do: config().http_status

  @doc "Gets service URLs configuration"
  @spec services() :: map()
  def services, do: config().services

  @doc "Gets RedisQ configuration"
  @spec redisq() :: map()
  def redisq, do: config().redisq

  @doc "Gets parser configuration"
  @spec parser() :: map()
  def parser, do: config().parser

  @doc "Gets enricher configuration"
  @spec enricher() :: map()
  def enricher, do: config().enricher

  @doc "Gets killmail store configuration"
  @spec killmail_store() :: map()
  def killmail_store, do: config().killmail_store

  @doc "Gets telemetry configuration"
  @spec telemetry() :: map()
  def telemetry, do: config().telemetry

  @doc "Gets application configuration"
  @spec app() :: map()
  def app, do: config().app

  # ============================================================================
  # Constants API
  # ============================================================================

  @doc """
  Gets GenServer call timeout in milliseconds.

  This is a true constant used for GenServer.call timeouts.
  For HTTP request timeouts, use `Config.timeouts().default_request_ms`.
  """
  @spec gen_server_call_timeout() :: integer()
  def gen_server_call_timeout, do: @gen_server_call_timeout

  @doc """
  Gets retry base delay in milliseconds.

  This is an algorithmic constant for exponential backoff calculations.
  """
  @spec retry_base_delay() :: integer()
  def retry_base_delay, do: @default_base_delay

  @doc """
  Gets maximum retry delay in milliseconds.

  This is an algorithmic constant for exponential backoff calculations.
  """
  @spec retry_max_delay() :: integer()
  def retry_max_delay, do: @max_backoff_delay

  @doc """
  Gets retry backoff factor.

  This is an algorithmic constant for exponential backoff calculations.
  """
  @spec retry_backoff_factor() :: integer()
  def retry_backoff_factor, do: @backoff_factor

  @doc """
  Gets validation limits.
  """
  @spec validation(atom()) :: integer()
  def validation(type) do
    case type do
      :max_killmail_id -> @max_killmail_id
      :max_system_id -> @max_system_id
      :max_character_id -> @max_character_id
    end
  end

  # Legacy compatibility functions (deprecated)
  @doc false
  @deprecated "Use Config.cache().killmails_ttl instead"
  def cache_ttl(:killmails), do: cache().killmails_ttl
  def cache_ttl(:system), do: cache().system_ttl
  def cache_ttl(:esi), do: cache().esi_ttl
  def cache_ttl(:esi_killmail), do: cache().esi_killmail_ttl

  @doc false
  @deprecated "Use Config.batch().concurrency_* instead"
  def batch_concurrency(:esi), do: batch().concurrency_esi
  def batch_concurrency(:zkb), do: batch().concurrency_zkb
  def batch_concurrency(_), do: batch().concurrency_default

  @doc false
  @deprecated "Use Config.timeouts().* instead"
  def request_timeout(:esi), do: timeouts().esi_request_ms
  def request_timeout(:zkb), do: timeouts().zkb_request_ms
  def request_timeout(:http), do: timeouts().http_request_ms
  def request_timeout(_), do: timeouts().default_request_ms

  @doc false
  @deprecated "Use Config.retry().http_max_retries instead"
  def retry_http_max_retries, do: retry().http_max_retries

  @doc false
  @deprecated "Use Config.retry().http_base_delay instead"
  def retry_http_base_delay, do: retry().http_base_delay

  @doc false
  @deprecated "Use Config.retry().http_max_delay instead"
  def retry_http_max_delay, do: retry().http_max_delay

  @doc false
  @deprecated "Use Config.app().port instead"
  def port, do: app().port

  @doc false
  @deprecated "Use Config.app().http_client instead"
  def http_client do
    case app().http_client do
      module when is_atom(module) ->
        module

      module_string when is_binary(module_string) ->
        String.to_existing_atom("Elixir.#{module_string}")
    end
  end

  # Additional legacy functions for compatibility
  @doc false
  def start_preloader?, do: get_env(:start_preloader, true)

  @doc false
  def clock, do: get_env(:clock, nil)

  @doc false
  def cache_killmails_name, do: get_env(:cache_killmails_name, :unified_cache)

  @doc false
  def cache_system_name, do: get_env(:cache_system_name, :system_cache)

  @doc false
  def cache_esi_name, do: get_env(:cache_esi_name, :esi_cache)

  @doc false
  @deprecated "Use Config.services().esi_base_url instead"
  def service_url(:esi), do: services().esi_base_url
  def service_url(_), do: nil

  # Private helper function
  defp get_env(key, default) do
    Application.get_env(:wanderer_kills, key, default)
  end
end
