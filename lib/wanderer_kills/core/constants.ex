defmodule WandererKills.Core.Constants do
  @moduledoc """
  Core constants for WandererKills.

  This module contains all core constants including
  timeout values, HTTP status codes, validation limits, retry configurations,
  and other technical constants.
  """

  # =============================================================================
  # Timeout Configuration (Use Config module for runtime-configurable timeouts)
  # =============================================================================

  @gen_server_call_timeout 5_000

  # =============================================================================
  # Retry Configuration (Use Config module for runtime-configurable retry settings)
  # =============================================================================

  @default_base_delay 1_000
  @max_backoff_delay 60_000
  @backoff_factor 2

  # =============================================================================
  # Validation Limits
  # =============================================================================

  # Validation Limits
  @max_killmail_id 999_999_999_999
  @max_system_id 32_000_000
  @max_character_id 999_999_999_999

  # =============================================================================
  # Public API - Timeout Configuration
  # =============================================================================

  @doc """
  Gets GenServer call timeout in milliseconds.

  This is a true constant used for GenServer.call timeouts.
  For HTTP request timeouts, use `WandererKills.Core.Config.request_timeout/1`.
  """
  @spec gen_server_call_timeout() :: integer()
  def gen_server_call_timeout, do: @gen_server_call_timeout

  # =============================================================================
  # Public API - Retry Configuration
  # =============================================================================

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

end
