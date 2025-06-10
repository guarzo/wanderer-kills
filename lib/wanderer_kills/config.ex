defmodule WandererKills.Config do
  @moduledoc """
  Simplified configuration wrapper for WandererKills.

  This module provides direct access to application configuration
  using `Application.get_env/3` with sensible defaults.
  """

  @app_name :wanderer_kills

  @doc """
  Get a configuration value by key with optional default.

  ## Examples
      
      Config.get(:port, 4004)
      Config.get([:cache, :killmails_ttl], 3600)
  """
  def get(key, default \\ nil)

  def get(key, default) when is_atom(key) do
    Application.get_env(@app_name, key, default)
  end

  def get([key | path], default) when is_atom(key) do
    @app_name
    |> Application.get_env(key, %{})
    |> get_in(path)
    |> case do
      nil -> default
      value -> value
    end
  end

  @doc """
  Get all configuration for the application.
  """
  def all do
    Application.get_all_env(@app_name)
  end

  # Convenience functions for common config groups

  def cache do
    %{
      killmails_ttl: get(:cache_killmails_ttl, 3600),
      system_ttl: get(:cache_system_ttl, 1800),
      esi_ttl: get(:cache_esi_ttl, 3600),
      system_recent_fetch_threshold: get(:cache_system_recent_fetch_threshold, 5)
    }
  end

  def retry do
    %{
      http_max_retries: get(:retry_http_max_retries, 3),
      http_base_delay: get(:retry_http_base_delay, 1000),
      http_max_delay: get(:retry_http_max_delay, 30_000),
      redisq_max_retries: get(:retry_redisq_max_retries, 5),
      redisq_base_delay: get(:retry_redisq_base_delay, 500)
    }
  end

  def app do
    %{
      port: get(:port, 4004),
      http_client: get(:http_client, WandererKills.Http.Client),
      zkb_client: get(:zkb_client, WandererKills.Killmails.ZkbClient),
      start_preloader: get(:start_preloader, true),
      start_redisq: get(:start_redisq, true)
    }
  end

  def esi do
    %{
      base_url: get(:esi_base_url, "https://esi.evetech.net/latest"),
      request_timeout_ms: get(:esi_request_timeout_ms, 30_000),
      batch_concurrency: get(:esi_batch_concurrency, 10)
    }
  end

  def zkb do
    %{
      base_url: get(:zkb_base_url, "https://zkillboard.com/api"),
      request_timeout_ms: get(:zkb_request_timeout_ms, 15_000),
      batch_concurrency: get(:zkb_batch_concurrency, 5)
    }
  end

  def redisq do
    %{
      base_url: get(:redisq_base_url, "https://zkillredisq.stream/listen.php"),
      fast_interval_ms: get(:redisq_fast_interval_ms, 1_000),
      idle_interval_ms: get(:redisq_idle_interval_ms, 5_000),
      initial_backoff_ms: get(:redisq_initial_backoff_ms, 1_000),
      max_backoff_ms: get(:redisq_max_backoff_ms, 30_000),
      backoff_factor: get(:redisq_backoff_factor, 2),
      task_timeout_ms: get(:redisq_task_timeout_ms, 10_000)
    }
  end

  def parser do
    %{
      cutoff_seconds: get(:parser_cutoff_seconds, 3_600),
      summary_interval_ms: get(:parser_summary_interval_ms, 60_000)
    }
  end

  def enricher do
    %{
      max_concurrency: get(:enricher_max_concurrency, 10),
      task_timeout_ms: get(:enricher_task_timeout_ms, 30_000),
      min_attackers_for_parallel: get(:enricher_min_attackers_for_parallel, 3)
    }
  end

  def killmail_store do
    %{
      gc_interval_ms: get(:killmail_store_gc_interval_ms, 60_000),
      max_events_per_system: get(:killmail_store_max_events_per_system, 10_000)
    }
  end

  def telemetry do
    %{
      enabled_metrics: get(:telemetry_enabled_metrics, [:cache, :api, :circuit, :event]),
      sampling_rate: get(:telemetry_sampling_rate, 1.0),
      retention_period: get(:telemetry_retention_period, 604_800)
    }
  end

  # Constants that shouldn't change at runtime
  def gen_server_call_timeout, do: 5_000
  def max_killmail_id, do: 999_999_999_999
  def max_system_id, do: 32_000_000
  def max_character_id, do: 999_999_999_999
  def max_subscribed_systems, do: 100

  # Validation helper
  def validation(:max_subscribed_systems), do: max_subscribed_systems()
  def validation(:max_killmail_id), do: max_killmail_id()
  def validation(:max_system_id), do: max_system_id()
  def validation(:max_character_id), do: max_character_id()

  # Compatibility helpers
  def start_preloader?, do: get(:start_preloader, true)
  def start_redisq?, do: get(:start_redisq, true)

  def services do
    %{
      esi_base_url: get(:esi_base_url, "https://esi.evetech.net/latest"),
      zkb_base_url: get(:zkb_base_url, "https://zkillboard.com/api"),
      redisq_base_url: get(:redisq_base_url, "https://zkillredisq.stream/listen.php")
    }
  end

  def batch do
    %{
      concurrency_esi: get(:esi_batch_concurrency, 10),
      concurrency_zkb: get(:zkb_batch_concurrency, 5),
      concurrency_default: get(:concurrency_batch_size, 100)
    }
  end

  def timeouts do
    %{
      esi_request_ms: get(:esi_request_timeout_ms, 30_000),
      zkb_request_ms: get(:zkb_request_timeout_ms, 15_000),
      http_request_ms: get(:http_request_timeout_ms, 10_000),
      default_request_ms: get(:default_request_timeout_ms, 10_000)
    }
  end
end
