defmodule WandererKills.Config do
  @moduledoc """
  Configuration helpers and constants for WandererKills.
  
  This module provides only computed defaults and application constants.
  All configuration should be accessed using standard Elixir patterns:
  
  - Compile-time: `Application.compile_env(:wanderer_kills, [:group, :key], default)`
  - Runtime: `Application.get_env(:wanderer_kills, :group, [])[:key]`
  
  ## Usage
  
      # Compile-time configuration (preferred for performance)
      @cache_ttl Application.compile_env(:wanderer_kills, [:cache, :killmails_ttl], 3600)
      
      # Runtime configuration (when needed)
      ttl = Application.get_env(:wanderer_kills, :cache, [])[:killmails_ttl] || 3600
      
      # Constants from this module
      max_id = WandererKills.Config.max_killmail_id()
  """

  # Application constants that shouldn't change
  @max_killmail_id 999_999_999_999
  @max_system_id 34_999_999
  @max_character_id 2_129_999_999
  @max_subscribed_systems 100
  @gen_server_call_timeout 5_000

  # User agent for API calls
  @user_agent "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"

  @doc "Maximum valid killmail ID"
  def max_killmail_id, do: @max_killmail_id

  @doc "Maximum valid system ID in EVE"
  def max_system_id, do: @max_system_id

  @doc "Maximum valid character ID in EVE"
  def max_character_id, do: @max_character_id

  @doc "Maximum number of systems a subscription can monitor"
  def max_subscribed_systems, do: @max_subscribed_systems

  @doc "Default GenServer call timeout"
  def gen_server_call_timeout, do: @gen_server_call_timeout

  @doc "User agent string for API requests"
  def user_agent, do: @user_agent

  @doc """
  Get the configured HTTP port for the endpoint.
  This is a computed value from Phoenix endpoint configuration.
  """
  def endpoint_port do
    case Application.get_env(:wanderer_kills, WandererKillsWeb.Endpoint, [])[:http] do
      nil -> 4004
      http_config when is_list(http_config) -> Keyword.get(http_config, :port, 4004)
      _ -> 4004
    end
  end

  @doc """
  Check if RedisQ service should start.
  This is commonly checked at runtime based on environment.
  """
  def start_redisq? do
    services = Application.get_env(:wanderer_kills, :services, [])
    Keyword.get(services, :start_redisq, true)
  end

  @doc """
  Check if event streaming is enabled.
  This is a runtime check for the storage module.
  """
  def event_streaming_enabled? do
    storage = Application.get_env(:wanderer_kills, :storage, [])
    Keyword.get(storage, :enable_event_streaming, true)
  end
end