defmodule WandererKills.Core.Constants do
  @moduledoc """
  Core constants for WandererKills.

  This module contains all core constants including
  timeout values, HTTP status codes, validation limits, retry configurations,
  and other technical constants.
  """

  # =============================================================================
  # HTTP Configuration
  # =============================================================================

  # HTTP Status Codes
  @http_success_codes 200..299
  @http_not_found 404
  @http_rate_limited 429
  @http_retryable_codes [408, 429, 500, 502, 503, 504]
  @http_fatal_codes [400, 401, 403, 405]

  # =============================================================================
  # Timeout Configuration
  # =============================================================================

  # Timeout Values (in milliseconds)
  @default_http_timeout 30_000
  @esi_request_timeout 10_000
  @zkb_request_timeout 15_000
  @parser_task_timeout 30_000
  @enricher_task_timeout 30_000
  @gen_server_call_timeout 5_000

  # =============================================================================
  # Retry Configuration
  # =============================================================================

  # Retry Configuration
  @default_max_retries 3
  @default_base_delay 1_000
  @max_backoff_delay 60_000
  @backoff_factor 2

  # =============================================================================
  # Concurrency Configuration
  # =============================================================================

  # Concurrency Limits
  @default_max_concurrency 10
  @parser_max_concurrency 20
  @enricher_max_concurrency 15
  @batch_size 100

  # =============================================================================
  # Validation Limits
  # =============================================================================

  # Validation Limits
  @max_killmail_id 999_999_999_999
  @max_system_id 32_000_000
  @max_character_id 999_999_999_999

  # =============================================================================
  # Telemetry Configuration
  # =============================================================================

  # Telemetry Defaults
  @default_sampling_rate 1.0
  @default_retention_period 604_800

  # =============================================================================
  # Public API - HTTP Configuration
  # =============================================================================

  @doc """
  Gets HTTP status code configuration.
  """
  @spec http_status(atom()) :: Range.t() | integer() | [integer()] | map()
  def http_status(type) do
    case type do
      :success -> @http_success_codes
      :not_found -> @http_not_found
      :rate_limited -> @http_rate_limited
      :retryable -> @http_retryable_codes
      :fatal -> @http_fatal_codes
    end
  end

  # =============================================================================
  # Public API - Timeout Configuration
  # =============================================================================

  @doc """
  Gets timeout configuration in milliseconds.
  """
  @spec timeout(atom()) :: integer()
  def timeout(type) do
    case type do
      :http -> @default_http_timeout
      :esi -> @esi_request_timeout
      :zkb -> @zkb_request_timeout
      :parser -> @parser_task_timeout
      :enricher -> @enricher_task_timeout
      :gen_server_call -> @gen_server_call_timeout
    end
  end

  # =============================================================================
  # Public API - Retry Configuration
  # =============================================================================

  @doc """
  Gets retry configuration.
  """
  @spec retry(atom()) :: integer()
  def retry(type) do
    case type do
      :max_retries -> @default_max_retries
      :base_delay -> @default_base_delay
      :max_delay -> @max_backoff_delay
      :factor -> @backoff_factor
    end
  end

  # =============================================================================
  # Public API - Concurrency Configuration
  # =============================================================================

  @doc """
  Gets concurrency configuration.
  """
  @spec concurrency(atom()) :: integer()
  def concurrency(type) do
    case type do
      :default -> @default_max_concurrency
      :parser -> @parser_max_concurrency
      :enricher -> @enricher_max_concurrency
      :batch_size -> @batch_size
    end
  end

  # =============================================================================
  # Public API - Validation Configuration
  # =============================================================================

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

  # =============================================================================
  # Public API - Telemetry Configuration
  # =============================================================================

  @doc """
  Gets telemetry configuration.
  """
  @spec telemetry(atom()) :: float() | integer() | map()
  def telemetry(type) do
    case type do
      :sampling_rate ->
        @default_sampling_rate

      :retention_period ->
        @default_retention_period

      :defaults ->
        %{
          sampling_rate: @default_sampling_rate,
          retention_period: @default_retention_period
        }
    end
  end
end
