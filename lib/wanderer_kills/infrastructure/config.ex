defmodule WandererKills.Infrastructure.Config do
  @moduledoc """
  Centralized configuration access for WandererKills infrastructure.

  This module provides clean access to application configuration using
  the flattened configuration structure. It replaces nested map drilling
  with simple, consistent access patterns.

  ## Usage

  ```elixir
  # Cache configuration
  ttl = Config.cache_ttl(:killmails)  # Uses cache_killmails_ttl

  # Retry configuration
  max_retries = Config.retry_http_max_retries()  # Uses retry_http_max_retries

  # HTTP status checking
  Config.http_status(:retryable)  # Uses http_status_retryable

  # Service URLs
  Config.redisq(:base_url)  # Uses redisq_base_url
  ```
  """

  # Simple, consistent access patterns for flattened config

  @doc "Gets cache TTL for a specific cache type"
  @spec cache_ttl(atom()) :: pos_integer()
  def cache_ttl(type) do
    case type do
      :killmails -> get(:cache_killmails_ttl, 3600)
      :system -> get(:cache_system_ttl, 1800)
      :esi -> get(:cache_esi_ttl, 3600)
    end
  end

  @doc "Gets retry configuration for HTTP requests"
  @spec retry_http_max_retries() :: pos_integer()
  def retry_http_max_retries, do: get(:retry_http_max_retries, 3)

  @doc "Gets retry base delay for HTTP requests"
  @spec retry_http_base_delay() :: pos_integer()
  def retry_http_base_delay, do: get(:retry_http_base_delay, 1000)

  @doc "Gets retry max delay for HTTP requests"
  @spec retry_http_max_delay() :: pos_integer()
  def retry_http_max_delay, do: get(:retry_http_max_delay, 30_000)

  @doc "Gets retry configuration for RedisQ"
  @spec retry_redisq_max_retries() :: pos_integer()
  def retry_redisq_max_retries, do: get(:retry_redisq_max_retries, 5)

  @doc "Gets retry base delay for RedisQ"
  @spec retry_redisq_base_delay() :: pos_integer()
  def retry_redisq_base_delay, do: get(:retry_redisq_base_delay, 500)

  @doc "Gets HTTP status configuration"
  @spec http_status(atom()) :: term()
  def http_status(type) do
    case type do
      :success -> get(:http_status_success, 200..299)
      :not_found -> get(:http_status_not_found, 404)
      :rate_limited -> get(:http_status_rate_limited, 429)
      :retryable -> get(:http_status_retryable, [408, 429, 500, 502, 503, 504])
      :fatal -> get(:http_status_fatal, [400, 401, 403, 405])
    end
  end

  @doc "Gets RedisQ configuration"
  @spec redisq(atom()) :: term()
  def redisq(key) do
    case key do
      :base_url -> get(:redisq_base_url)
      :fast_interval_ms -> get(:redisq_fast_interval_ms, 1_000)
      :idle_interval_ms -> get(:redisq_idle_interval_ms, 5_000)
      :initial_backoff_ms -> get(:redisq_initial_backoff_ms, 1_000)
      :max_backoff_ms -> get(:redisq_max_backoff_ms, 30_000)
      :backoff_factor -> get(:redisq_backoff_factor, 2)
      :task_timeout_ms -> get(:redisq_task_timeout_ms, 10_000)
    end
  end

  @doc "Gets ESI configuration"
  @spec esi(atom()) :: term()
  def esi(key) do
    case key do
      :base_url -> get(:esi_base_url, "https://esi.evetech.net/latest")
    end
  end

  @doc "Gets zKillboard configuration"
  @spec zkb(atom()) :: term()
  def zkb(key) do
    case key do
      :base_url -> get(:zkb_base_url, "https://zkillboard.com/api")
    end
  end

  @doc "Gets parser configuration"
  @spec parser(atom()) :: term()
  def parser(key) do
    case key do
      :cutoff_seconds -> get(:parser_cutoff_seconds, 3_600)
      :summary_interval_ms -> get(:parser_summary_interval_ms, 60_000)
    end
  end

  @doc "Gets parser cutoff seconds directly"
  @spec parser_cutoff_seconds() :: pos_integer()
  def parser_cutoff_seconds, do: get(:parser_cutoff_seconds, 3_600)

  @doc "Gets enricher configuration"
  @spec enricher(atom()) :: term()
  def enricher(key) do
    case key do
      :max_concurrency -> get(:enricher_max_concurrency, 10)
      :task_timeout_ms -> get(:enricher_task_timeout_ms, 30_000)
      :min_attackers_for_parallel -> get(:enricher_min_attackers_for_parallel, 3)
    end
  end

  @doc "Gets concurrency configuration"
  @spec concurrency(atom()) :: term()
  def concurrency(key) do
    case key do
      :batch_size -> get(:concurrency_batch_size, 100)
    end
  end

  @doc "Gets killmail store configuration"
  @spec killmail_store(atom()) :: term()
  def killmail_store(key) do
    case key do
      :gc_interval_ms -> get(:killmail_store_gc_interval_ms, 60_000)
      :max_events_per_system -> get(:killmail_store_max_events_per_system, 10_000)
    end
  end

  @doc "Gets circuit breaker configuration"
  @spec circuit_breaker(atom()) :: pos_integer()
  def circuit_breaker(service) do
    case service do
      :zkb -> get(:circuit_breaker_zkb_failure_threshold, 10)
      :esi -> get(:circuit_breaker_esi_failure_threshold, 5)
    end
  end

  @doc "Gets telemetry configuration"
  @spec telemetry(atom()) :: term()
  def telemetry(key) do
    case key do
      :enabled_metrics -> get(:telemetry_enabled_metrics, [:cache, :api, :circuit, :event])
      :sampling_rate -> get(:telemetry_sampling_rate, 1.0)
      :retention_period -> get(:telemetry_retention_period, 604_800)
    end
  end

  @doc "Gets application port"
  @spec port() :: pos_integer()
  def port, do: get(:port, 4004)

  @doc "Gets HTTP client module"
  @spec http_client() :: module()
  def http_client, do: get(:http_client, WandererKills.Http.Client)

  @doc "Gets zKillboard client module"
  @spec zkb_client() :: module()
  def zkb_client, do: get(:zkb_client, WandererKills.External.Zkb.Client)

  @doc "Gets system cache recent fetch threshold"
  @spec recent_fetch_threshold() :: pos_integer()
  def recent_fetch_threshold, do: get(:cache_system_recent_fetch_threshold, 5)

  @doc "Checks if preloader should start (for testing)"
  @spec start_preloader?() :: boolean()
  def start_preloader?, do: get(:start_preloader, true)

  @doc "Checks if RedisQ should start (for testing)"
  @spec start_redisq?() :: boolean()
  def start_redisq?, do: get(:start_redisq, true)

  @doc "Gets cache name for killmails"
  @spec cache_killmails_name() :: atom()
  def cache_killmails_name, do: get(:cache_killmails_name, :unified_cache)

  @doc "Gets cache name for system data"
  @spec cache_system_name() :: atom()
  def cache_system_name, do: get(:cache_system_name, :system_cache)

  @doc "Gets cache name for ESI data"
  @spec cache_esi_name() :: atom()
  def cache_esi_name, do: get(:cache_esi_name, :esi_cache)

  @doc "Public access to configuration (for compatibility)"
  @spec get(atom()) :: term()
  def get(key) when is_atom(key), do: Application.get_env(:wanderer_kills, key)

  # Generic configuration access helper
  defp get(key, default) do
    Application.get_env(:wanderer_kills, key, default)
  end
end
