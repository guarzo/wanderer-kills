defmodule WandererKills.Config do
  @moduledoc """
  Centralized configuration management for the application.
  Provides access to both compile-time and runtime configuration values.
  """

  alias WandererKills.Constants

  # Compile-time configuration
  @zkb_base_url Application.compile_env(:wanderer_kills, [:zkb, :base_url])
  @port Application.compile_env(:wanderer_kills, :port)

  # Runtime configuration accessors
  def zkb_base_url, do: @zkb_base_url
  def port, do: @port

  @type cache_type :: :killmails | :system | :esi
  @type cache_key :: atom()

  # Cache configuration
  @doc """
  Gets the cache configuration for a specific cache type.
  """
  @spec cache(cache_type()) :: map()
  def cache(cache_type) do
    case cache_type do
      :killmails -> get_killmail_cache_config()
      :system -> get_system_cache_config()
      :esi -> get_esi_cache_config()
    end
  end

  @doc """
  Gets the cache configuration for a specific cache type and key.
  """
  @spec cache(cache_type(), cache_key()) :: term()
  def cache(cache_type, key) do
    case cache_type do
      :killmails -> get_killmail_cache_config(key)
      :system -> get_system_cache_config(key)
      :esi -> get_esi_cache_config(key)
    end
  end

  @doc """
  Gets the cache configuration.
  """
  @spec cache() :: %{killmails: map(), system: map(), esi: map()}
  def cache do
    %{
      killmails: get_killmail_cache_config(),
      system: get_system_cache_config(),
      esi: get_esi_cache_config()
    }
  end

  @doc """
  Gets the recent fetch threshold in seconds.
  """
  @spec recent_fetch_threshold() :: pos_integer()
  def recent_fetch_threshold do
    Application.get_env(:wanderer_kills, :cache_system_recent_fetch_threshold, 5)
  end

  @doc false
  @spec get_killmail_cache_config(cache_key() | nil) :: term()
  defp get_killmail_cache_config(key \\ nil) do
    config = Application.get_env(:wanderer_kills, :cache_killmails, %{})
    if key, do: Map.get(config, key), else: config
  end

  @doc false
  @spec get_system_cache_config(cache_key() | nil) :: term()
  defp get_system_cache_config(key \\ nil) do
    config = Application.get_env(:wanderer_kills, :cache_system, %{})
    if key, do: Map.get(config, key), else: config
  end

  @doc false
  @spec get_esi_cache_config(cache_key() | nil) :: term()
  defp get_esi_cache_config(key \\ nil) do
    config = Application.get_env(:wanderer_kills, :cache_esi, %{})
    if key, do: Map.get(config, key), else: config
  end

  # Retry configuration
  def retry do
    Application.get_env(:wanderer_kills, :retry, %{})
  end

  def retry_config(type) do
    Constants.retry_config(type)
  end

  # Timeout configuration
  def timeout(type) do
    Constants.timeout(type)
  end

  # Concurrency configuration
  def concurrency do
    Application.get_env(:wanderer_kills, :concurrency, %{})
  end

  def concurrency(type) do
    Constants.concurrency(type)
  end

  # System thresholds
  def threshold(type) do
    Constants.threshold(type)
  end

  # HTTP status codes
  def http_status(type) do
    Constants.http_status(type)
  end

  # Validation limits
  def validation(type) do
    Constants.validation(type)
  end

  # Circuit breaker configuration
  def circuit_breaker(service) do
    defaults = Constants.circuit_breaker(:defaults)
    service_config = Application.get_env(:wanderer_kills, [:circuit_breaker, service], %{})
    Map.merge(defaults, service_config)
  end

  # Telemetry configuration
  def telemetry do
    defaults = Constants.telemetry(:defaults)
    config = Application.get_env(:wanderer_kills, :telemetry, %{})
    Map.merge(defaults, config)
  end

  # Killmail store configuration
  def killmail_store do
    Application.get_env(:wanderer_kills, :killmail_store, %{})
  end

  # ESI API configuration
  def esi do
    Application.get_env(:wanderer_kills, :esi, %{})
  end

  # RedisQ stream configuration
  def redisq do
    Application.get_env(:wanderer_kills, :redisq, %{})
  end

  # Parser configuration
  def parser do
    Application.get_env(:wanderer_kills, :parser, %{})
  end

  # Enricher configuration
  def enricher do
    Application.get_env(:wanderer_kills, :enricher, %{})
  end

  # Clock configuration
  def clock do
    Application.get_env(:wanderer_kills, :clock, %{})
  end
end
