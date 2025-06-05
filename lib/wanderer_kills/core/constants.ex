defmodule WandererKills.Core.Constants do
  @moduledoc """
  Centralized constants and configuration values for the application.

  This module provides a single source of truth for all magic numbers,
  timeouts, and other constant values used throughout the application.
  """

  # Cache TTLs
  def cache_ttl(:killmails), do: :timer.hours(24)
  def cache_ttl(:system), do: :timer.hours(1)
  def cache_ttl(:esi), do: :timer.hours(48)

  # Retry Configuration
  def retry_config(:http) do
    [
      max_retries: 3,
      base_backoff: 1_000,
      max_backoff: 30_000
    ]
  end

  def retry_config(:redisq) do
    [
      max_retries: 5,
      base_backoff: 1_000,
      max_backoff: 30_000,
      backoff_factor: 2
    ]
  end

  # Timeouts
  def timeout(:gen_server_call), do: 30_000
  def timeout(:gen_server_cast), do: 5_000
  def timeout(:task), do: 10_000
  def timeout(:http_request), do: 15_000
  def timeout(:enricher_task), do: 30_000

  # Concurrency Limits
  def concurrency(:max_concurrent), do: 10
  def concurrency(:batch_size), do: 50
  def concurrency(:enricher_max), do: 10
  def concurrency(:min_attackers_for_parallel), do: 3

  # System Thresholds
  def threshold(:recent_fetch_ms), do: 300_000
  def threshold(:parser_cutoff_seconds), do: 3_600
  def threshold(:summary_interval_ms), do: 60_000

  # HTTP Status Codes
  def http_status(:success), do: 200..299
  def http_status(:not_found), do: 404
  def http_status(:rate_limited), do: 429
  def http_status(:retryable), do: [408, 429, 500, 502, 503, 504]

  def http_status(:fatal) do
    [
      400,
      401,
      403,
      405,
      406,
      407,
      409,
      410,
      411,
      412,
      413,
      414,
      415,
      416,
      417,
      418,
      421,
      422,
      423,
      424,
      426,
      428,
      431,
      451
    ]
  end

  # Validation limits
  def validation(:client_id_max_length), do: 50
  def validation(:system_id_min), do: 30_000_000
  def validation(:system_id_max), do: 40_000_000
  def validation(:max_client_id_length), do: 50
  def validation(:min_system_id), do: 30_000_000
  def validation(:max_system_id), do: 40_000_000

  # Circuit Breaker Defaults
  def circuit_breaker(:defaults) do
    %{
      failure_threshold: 5,
      cooldown_period: 30_000,
      half_open_timeout: 5_000
    }
  end

  def circuit_breaker(:failure_threshold), do: 5
  def circuit_breaker(:cooldown_period), do: 30_000
  def circuit_breaker(:half_open_timeout), do: 5_000

  # Telemetry Settings
  def telemetry(:defaults) do
    %{
      sampling_rate: 1.0,
      # 7 days in seconds
      retention_period: 7 * 24 * 60 * 60,
      enabled_metrics: [:request_count, :error_count, :latency]
    }
  end

  def telemetry(:sampling_rate), do: 1.0
  # 7 days in seconds
  def telemetry(:retention_period), do: 7 * 24 * 60 * 60
  def telemetry(:enabled_metrics), do: [:request_count, :error_count, :latency]
end
