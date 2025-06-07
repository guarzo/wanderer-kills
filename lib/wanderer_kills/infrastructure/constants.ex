defmodule WandererKills.Infrastructure.Constants do
  @moduledoc """
  Infrastructure constants for WandererKills.

  This module contains all infrastructure-wide constants including
  timeout values, HTTP status codes, validation limits, retry configurations,
  and other technical constants.

  This consolidates constants that were previously scattered across
  shared/constants.ex and provides a central place for infrastructure
  configuration constants.
  """

  # =============================================================================
  # HTTP Configuration
  # =============================================================================

  # HTTP Status Codes
  @http_success_codes 200..299
  @http_not_found 404
  @http_rate_limited 429
  @http_retryable_codes [408, 429, 500, 502, 503, 504]
  @http_fatal_codes [
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

  # =============================================================================
  # Timeout Configuration
  # =============================================================================

  # Timeout Values (in milliseconds)
  @default_http_timeout 30_000
  @esi_request_timeout 10_000
  @zkb_request_timeout 15_000
  @parser_task_timeout 30_000
  @enricher_task_timeout 30_000

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
  # System Thresholds
  # =============================================================================

  # System Thresholds
  @system_recent_fetch_threshold 5
  @max_killmails_per_request 100
  @max_systems_per_batch 50

  # =============================================================================
  # Validation Limits
  # =============================================================================

  # Validation Limits
  @max_killmail_id 999_999_999_999
  @max_system_id 32_000_000
  @max_character_id 999_999_999_999
  @max_corporation_id 999_999_999_999
  @max_alliance_id 999_999_999_999
  @max_type_id 999_999_999

  # =============================================================================
  # Circuit Breaker Configuration
  # =============================================================================

  # Circuit Breaker Defaults
  @default_failure_threshold 5
  @default_recovery_timeout 60_000
  @default_half_open_max_calls 3

  # =============================================================================
  # Telemetry Configuration
  # =============================================================================

  # Telemetry Defaults
  @default_sampling_rate 1.0
  # 7 days in seconds
  @default_retention_period 604_800

  # =============================================================================
  # Public API - HTTP Configuration
  # =============================================================================

  @doc """
  Gets HTTP status code configuration.

  ## Parameters
  - `type` - The type of status code configuration to retrieve

  ## Examples

  ```elixir
  success_range = Constants.http_status(:success)
  retryable_codes = Constants.http_status(:retryable)
  ```
  """
  @spec http_status(atom()) :: Range.t() | integer() | [integer()] | map()
  def http_status(type) do
    case type do
      :success ->
        @http_success_codes

      :not_found ->
        @http_not_found

      :rate_limited ->
        @http_rate_limited

      :retryable ->
        @http_retryable_codes

      :fatal ->
        @http_fatal_codes

      :defaults ->
        %{
          success: @http_success_codes,
          not_found: @http_not_found,
          rate_limited: @http_rate_limited,
          retryable: @http_retryable_codes,
          fatal: @http_fatal_codes
        }
    end
  end

  # =============================================================================
  # Public API - Timeout Configuration
  # =============================================================================

  @doc """
  Gets timeout configuration in milliseconds.

  ## Parameters
  - `type` - The type of timeout configuration to retrieve

  ## Examples

  ```elixir
  http_timeout = Constants.timeout(:http)
  esi_timeout = Constants.timeout(:esi)
  ```
  """
  @spec timeout(atom()) :: integer() | map()
  def timeout(type) do
    case type do
      :http ->
        @default_http_timeout

      :esi ->
        @esi_request_timeout

      :zkb ->
        @zkb_request_timeout

      :parser ->
        @parser_task_timeout

      :enricher ->
        @enricher_task_timeout

      :gen_server_call ->
        5_000

      :defaults ->
        %{
          http: @default_http_timeout,
          esi: @esi_request_timeout,
          zkb: @zkb_request_timeout,
          parser: @parser_task_timeout,
          enricher: @enricher_task_timeout,
          gen_server_call: 5_000
        }
    end
  end

  # =============================================================================
  # Public API - Retry Configuration
  # =============================================================================

  @doc """
  Gets retry configuration.

  ## Parameters
  - `type` - The type of retry configuration to retrieve

  ## Examples

  ```elixir
  http_config = Constants.retry_config(:http)
  esi_config = Constants.retry_config(:esi)
  ```
  """
  @spec retry_config(atom()) :: map()
  def retry_config(type) do
    case type do
      :http ->
        %{max_retries: @default_max_retries, base_delay: @default_base_delay}

      :esi ->
        %{max_retries: 3, base_delay: 2_000}

      :zkb ->
        %{max_retries: 5, base_delay: 1_000}

      :redisq ->
        %{max_retries: 5, base_delay: 500}

      :defaults ->
        %{
          max_retries: @default_max_retries,
          base_delay: @default_base_delay,
          max_backoff_delay: @max_backoff_delay,
          backoff_factor: @backoff_factor
        }
    end
  end

  # =============================================================================
  # Public API - Concurrency Configuration
  # =============================================================================

  @doc """
  Gets concurrency configuration.

  ## Parameters
  - `type` - The type of concurrency configuration to retrieve

  ## Examples

  ```elixir
  default_concurrency = Constants.concurrency(:default)
  parser_concurrency = Constants.concurrency(:parser)
  ```
  """
  @spec concurrency(atom()) :: integer() | map()
  def concurrency(type) do
    case type do
      :default ->
        @default_max_concurrency

      :parser ->
        @parser_max_concurrency

      :enricher ->
        @enricher_max_concurrency

      :batch_size ->
        @batch_size

      :defaults ->
        %{
          default: @default_max_concurrency,
          parser: @parser_max_concurrency,
          enricher: @enricher_max_concurrency,
          batch_size: @batch_size
        }
    end
  end

  # =============================================================================
  # Public API - System Thresholds
  # =============================================================================

  @doc """
  Gets system threshold configuration.

  ## Parameters
  - `type` - The type of threshold configuration to retrieve

  ## Examples

  ```elixir
  fetch_threshold = Constants.threshold(:recent_fetch)
  max_killmails = Constants.threshold(:max_killmails_per_request)
  ```
  """
  @spec threshold(atom()) :: integer() | map()
  def threshold(type) do
    case type do
      :recent_fetch ->
        @system_recent_fetch_threshold

      :max_killmails_per_request ->
        @max_killmails_per_request

      :max_systems_per_batch ->
        @max_systems_per_batch

      :defaults ->
        %{
          recent_fetch: @system_recent_fetch_threshold,
          max_killmails_per_request: @max_killmails_per_request,
          max_systems_per_batch: @max_systems_per_batch
        }
    end
  end

  # =============================================================================
  # Public API - Validation Limits
  # =============================================================================

  @doc """
  Gets validation limits.

  ## Parameters
  - `type` - The type of validation limit to retrieve

  ## Examples

  ```elixir
  max_killmail_id = Constants.validation(:max_killmail_id)
  max_system_id = Constants.validation(:max_system_id)
  ```
  """
  @spec validation(atom()) :: integer() | map()
  def validation(type) do
    case type do
      :max_killmail_id ->
        @max_killmail_id

      :max_system_id ->
        @max_system_id

      :max_character_id ->
        @max_character_id

      :max_corporation_id ->
        @max_corporation_id

      :max_alliance_id ->
        @max_alliance_id

      :max_type_id ->
        @max_type_id

      :defaults ->
        %{
          max_killmail_id: @max_killmail_id,
          max_system_id: @max_system_id,
          max_character_id: @max_character_id,
          max_corporation_id: @max_corporation_id,
          max_alliance_id: @max_alliance_id,
          max_type_id: @max_type_id
        }
    end
  end

  # =============================================================================
  # Public API - Circuit Breaker Configuration
  # =============================================================================

  @doc """
  Gets circuit breaker configuration.

  ## Parameters
  - `type` - The type of circuit breaker configuration to retrieve

  ## Examples

  ```elixir
  defaults = Constants.circuit_breaker(:defaults)
  zkb_config = Constants.circuit_breaker(:zkb)
  ```
  """
  @spec circuit_breaker(atom()) :: map()
  def circuit_breaker(type) do
    case type do
      :defaults ->
        %{
          failure_threshold: @default_failure_threshold,
          recovery_timeout: @default_recovery_timeout,
          half_open_max_calls: @default_half_open_max_calls
        }

      service when service in [:zkb, :esi, :redisq] ->
        %{
          failure_threshold: @default_failure_threshold,
          recovery_timeout: @default_recovery_timeout,
          half_open_max_calls: @default_half_open_max_calls
        }
    end
  end

  # =============================================================================
  # Public API - Telemetry Configuration
  # =============================================================================

  @doc """
  Gets telemetry configuration.

  ## Parameters
  - `type` - The type of telemetry configuration to retrieve

  ## Examples

  ```elixir
  defaults = Constants.telemetry(:defaults)
  sampling_rate = Constants.telemetry(:sampling_rate)
  ```
  """
  @spec telemetry(atom()) :: float() | integer() | map()
  def telemetry(type) do
    case type do
      :defaults ->
        %{
          sampling_rate: @default_sampling_rate,
          retention_period: @default_retention_period
        }

      :sampling_rate ->
        @default_sampling_rate

      :retention_period ->
        @default_retention_period
    end
  end
end
