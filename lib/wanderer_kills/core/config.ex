defmodule WandererKills.Core.Config do
  @moduledoc """
  Centralized configuration management for WandererKills.

  This module provides a unified interface for accessing application configuration,
  replacing scattered `Application.compile_env/3` calls throughout the codebase.
  It provides proper defaults, validation, and type checking.

  ## Usage

  ```elixir
  # Cache configuration
  ttl = Config.cache_ttl(:killmails)

  # Retry configuration
  max_retries = Config.retry_http_max_retries()

  # Service URLs
  base_url = Config.service_url(:esi)
  ```
  """

  @doc "Gets cache TTL for a specific cache type"
  @spec cache_ttl(atom()) :: pos_integer()
  def cache_ttl(type) do
    case type do
      :killmails -> get_env(:cache_killmails_ttl, 3600)
      :system -> get_env(:cache_system_ttl, 1800)
      :esi -> get_env(:cache_esi_ttl, 3600)
      :esi_killmail -> get_env(:cache_esi_killmail_ttl, 86_400)
    end
  end

  @doc "Gets batch concurrency for various services"
  @spec batch_concurrency(atom()) :: pos_integer()
  def batch_concurrency(service) do
    case service do
      :esi -> get_env(:esi_batch_concurrency, 10)
      :zkb -> get_env(:zkb_batch_concurrency, 5)
      _ -> get_env(:default_batch_concurrency, 5)
    end
  end

  @doc "Gets request timeout for various services"
  @spec request_timeout(atom()) :: pos_integer()
  def request_timeout(service) do
    case service do
      :esi -> get_env(:esi_request_timeout_ms, 30_000)
      :zkb -> get_env(:zkb_request_timeout_ms, 15_000)
      :http -> get_env(:http_request_timeout_ms, 10_000)
      _ -> get_env(:default_request_timeout_ms, 10_000)
    end
  end

  @doc "Gets retry configuration for HTTP requests"
  @spec retry_http_max_retries() :: pos_integer()
  def retry_http_max_retries, do: get_env(:retry_http_max_retries, 3)

  @doc "Gets retry base delay for HTTP requests"
  @spec retry_http_base_delay() :: pos_integer()
  def retry_http_base_delay, do: get_env(:retry_http_base_delay, 1000)

  @doc "Gets retry max delay for HTTP requests"
  @spec retry_http_max_delay() :: pos_integer()
  def retry_http_max_delay, do: get_env(:retry_http_max_delay, 30_000)

  @doc "Gets retry configuration for RedisQ"
  @spec retry_redisq_max_retries() :: pos_integer()
  def retry_redisq_max_retries, do: get_env(:retry_redisq_max_retries, 5)

  @doc "Gets retry base delay for RedisQ"
  @spec retry_redisq_base_delay() :: pos_integer()
  def retry_redisq_base_delay, do: get_env(:retry_redisq_base_delay, 500)

  @doc "Gets HTTP status configuration"
  @spec http_status(atom()) :: term()
  def http_status(type) do
    case type do
      :success -> get_env(:http_status_success, 200..299)
      :not_found -> get_env(:http_status_not_found, 404)
      :rate_limited -> get_env(:http_status_rate_limited, 429)
      :retryable -> get_env(:http_status_retryable, [408, 429, 500, 502, 503, 504])
      :fatal -> get_env(:http_status_fatal, [400, 401, 403, 405])
    end
  end

  @doc "Gets service URL configuration"
  @spec service_url(atom()) :: String.t()
  def service_url(service) do
    case service do
      :esi -> get_env(:esi_base_url, "https://esi.evetech.net/latest")
      :zkb -> get_env(:zkb_base_url, "https://zkillboard.com/api")
      :redisq -> get_env(:redisq_base_url, nil)
    end
  end

  @doc "Gets ESI configuration"
  @spec esi(atom()) :: term()
  def esi(key) do
    case key do
      :base_url -> get_env(:esi_base_url, "https://esi.evetech.net/latest")
    end
  end

  @doc "Gets zKillboard configuration"
  @spec zkb(atom()) :: term()
  def zkb(key) do
    case key do
      :base_url -> get_env(:zkb_base_url, "https://zkillboard.com/api")
    end
  end

  @doc "Gets RedisQ configuration"
  @spec redisq(atom()) :: term()
  def redisq(key) do
    case key do
      :base_url -> get_env(:redisq_base_url, nil)
      :fast_interval_ms -> get_env(:redisq_fast_interval_ms, 1_000)
      :idle_interval_ms -> get_env(:redisq_idle_interval_ms, 5_000)
      :initial_backoff_ms -> get_env(:redisq_initial_backoff_ms, 1_000)
      :max_backoff_ms -> get_env(:redisq_max_backoff_ms, 30_000)
      :backoff_factor -> get_env(:redisq_backoff_factor, 2)
      :task_timeout_ms -> get_env(:redisq_task_timeout_ms, 10_000)
    end
  end

  @doc "Gets parser configuration"
  @spec parser(atom()) :: term()
  def parser(key) do
    case key do
      :cutoff_seconds -> get_env(:parser_cutoff_seconds, 3_600)
      :summary_interval_ms -> get_env(:parser_summary_interval_ms, 60_000)
    end
  end

  @doc "Gets parser cutoff seconds directly"
  @spec parser_cutoff_seconds() :: pos_integer()
  def parser_cutoff_seconds, do: get_env(:parser_cutoff_seconds, 3_600)

  @doc "Gets enricher configuration"
  @spec enricher(atom()) :: term()
  def enricher(key) do
    case key do
      :max_concurrency -> get_env(:enricher_max_concurrency, 10)
      :task_timeout_ms -> get_env(:enricher_task_timeout_ms, 30_000)
      :min_attackers_for_parallel -> get_env(:enricher_min_attackers_for_parallel, 3)
    end
  end

  @doc "Gets concurrency configuration"
  @spec concurrency(atom()) :: term()
  def concurrency(key) do
    case key do
      :batch_size -> get_env(:concurrency_batch_size, 100)
    end
  end

  @doc "Gets killmail store configuration"
  @spec killmail_store(atom()) :: term()
  def killmail_store(key) do
    case key do
      :gc_interval_ms -> get_env(:killmail_store_gc_interval_ms, 60_000)
      :max_events_per_system -> get_env(:killmail_store_max_events_per_system, 10_000)
    end
  end

  @doc "Gets telemetry configuration"
  @spec telemetry(atom()) :: term()
  def telemetry(key) do
    case key do
      :enabled_metrics -> get_env(:telemetry_enabled_metrics, [:cache, :api, :circuit, :event])
      :sampling_rate -> get_env(:telemetry_sampling_rate, 1.0)
      :retention_period -> get_env(:telemetry_retention_period, 604_800)
    end
  end

  @doc "Gets application port"
  @spec port() :: pos_integer()
  def port, do: get_env(:port, 4004)

  @doc "Gets HTTP client module"
  @spec http_client() :: module()
  def http_client do
    case get_env(:http_client, "WandererKills.Core.Http.Client") do
      module when is_atom(module) ->
        module

      module_string when is_binary(module_string) ->
        String.to_existing_atom("Elixir.#{module_string}")
    end
  end

  @doc "Gets zKillboard client module"
  @spec zkb_client() :: module()
  def zkb_client, do: get_env(:zkb_client, WandererKills.Zkb.Client)

  @doc "Gets system cache recent fetch threshold"
  @spec recent_fetch_threshold() :: pos_integer()
  def recent_fetch_threshold, do: get_env(:cache_system_recent_fetch_threshold, 5)

  @doc "Checks if preloader should start (for testing)"
  @spec start_preloader?() :: boolean()
  def start_preloader?, do: get_env(:start_preloader, true)

  @doc "Checks if RedisQ should start (for testing)"
  @spec start_redisq?() :: boolean()
  def start_redisq?, do: get_env(:start_redisq, true)

  @doc "Gets cache name for killmails"
  @spec cache_killmails_name() :: atom()
  def cache_killmails_name, do: get_env(:cache_killmails_name, :unified_cache)

  @doc "Gets cache name for system data"
  @spec cache_system_name() :: atom()
  def cache_system_name, do: get_env(:cache_system_name, :system_cache)

  @doc "Gets cache name for ESI data"
  @spec cache_esi_name() :: atom()
  def cache_esi_name, do: get_env(:cache_esi_name, :esi_cache)

  @doc "Gets clock configuration (for test time mocking)"
  @spec clock() :: term()
  def clock, do: get_env(:clock, nil)

  @doc "Gets cache cleanup interval in milliseconds"
  @spec cache_cleanup_interval_ms() :: pos_integer()
  def cache_cleanup_interval_ms, do: get_env(:cache_cleanup_interval_ms, 300_000)

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Centralized configuration access with validation
  @spec get_env(atom(), term()) :: term()
  defp get_env(key, default) do
    case Application.get_env(:wanderer_kills, key, default) do
      nil when default != nil -> default
      value -> validate_config_value(key, value)
    end
  end

  # Basic validation for common configuration types
  @spec validate_config_value(atom(), term()) :: term()
  defp validate_config_value(key, value) when is_atom(key) do
    case key do
      key when key in [:port, :cache_killmails_ttl, :cache_system_ttl, :cache_esi_ttl] ->
        validate_positive_integer(key, value)

      key when key in [:retry_http_max_retries, :retry_redisq_max_retries] ->
        validate_positive_integer(key, value)

      key when key in [:parser_cutoff_seconds, :enricher_max_concurrency] ->
        validate_positive_integer(key, value)

      key when key in [:start_preloader, :start_redisq] ->
        validate_boolean(key, value)

      key when key in [:esi_base_url, :zkb_base_url] ->
        validate_string(key, value)

      _ ->
        value
    end
  end

  @spec validate_positive_integer(atom(), term()) :: pos_integer()
  defp validate_positive_integer(_key, value) when is_integer(value) and value > 0, do: value

  defp validate_positive_integer(key, value) do
    raise ArgumentError, "Configuration #{key} must be a positive integer, got: #{inspect(value)}"
  end

  @spec validate_boolean(atom(), term()) :: boolean()
  defp validate_boolean(_key, value) when is_boolean(value), do: value

  defp validate_boolean(key, value) do
    raise ArgumentError, "Configuration #{key} must be a boolean, got: #{inspect(value)}"
  end

  @spec validate_string(atom(), term()) :: String.t()
  defp validate_string(_key, value) when is_binary(value), do: value

  defp validate_string(key, value) do
    raise ArgumentError, "Configuration #{key} must be a string, got: #{inspect(value)}"
  end
end
