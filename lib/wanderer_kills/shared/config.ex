defmodule WandererKills.Config do
  @moduledoc """
  Simplified configuration management for WandererKills.

  This module provides clean access to application configuration without
  unnecessary abstractions. It replaces the previous Core.Config module
  with simpler, more direct configuration access patterns.

  ## Usage

  ```elixir
  # Get configuration values
  port = Config.get(:port)
  cache_config = Config.get(:cache)
  esi_config = Config.get(:esi)

  # Get with default
  timeout = Config.get(:timeout, 5000)

  # Get nested values
  zkb_url = Config.get([:zkb, :base_url])
  killmail_ttl = Config.get([:cache, :killmails, :ttl])
  ```
  """

  @doc """
  Gets a configuration value for the :wanderer_kills application.

  ## Parameters
  - `key` - Configuration key (atom or list of atoms for nested values)
  - `default` - Default value if key is not found (optional)

  ## Examples

  ```elixir
  port = Config.get(:port)
  cache_config = Config.get(:cache)
  zkb_url = Config.get([:zkb, :base_url])
  timeout = Config.get(:request_timeout, 5000)
  ```
  """
  @spec get(atom() | [atom()], term()) :: term()
  def get(key, default \\ nil)

  def get(key, default) when is_atom(key) do
    Application.get_env(:wanderer_kills, key, default)
  end

  def get(keys, default) when is_list(keys) do
    case keys do
      [key] -> get(key, default)
      [key | rest] -> get_nested(get(key), rest, default)
    end
  end

  @doc """
  Gets cache configuration for a specific cache type.

  ## Parameters
  - `cache_type` - Type of cache (:killmails, :system, :esi)

  ## Returns
  Cache configuration map or empty map if not found
  """
  @spec cache_config(atom()) :: map()
  def cache_config(cache_type) do
    get([:cache, cache_type], %{})
  end

  @doc """
  Gets the TTL (time-to-live) for a specific cache type.

  ## Parameters
  - `cache_type` - Type of cache (:killmails, :system, :esi)

  ## Returns
  TTL in seconds or default value (3600 seconds = 1 hour)
  """
  @spec cache_ttl(atom()) :: pos_integer()
  def cache_ttl(cache_type) do
    get([:cache, cache_type, :ttl], 3600)
  end

  @doc """
  Gets retry configuration for a specific service.

  ## Parameters
  - `service` - Service name (:http, :redisq, etc.)

  ## Returns
  Retry configuration map
  """
  @spec retry_config(atom()) :: map()
  def retry_config(service) do
    # First check application config, then fall back to constants
    case get([:retry, service]) do
      nil -> WandererKills.Constants.retry_config(service)
      config -> config
    end
  end

  @doc """
  Gets circuit breaker configuration for a specific service.

  ## Parameters
  - `service` - Service name (:zkb, :esi, etc.)

  ## Returns
  Circuit breaker configuration map
  """
  @spec circuit_breaker_config(atom()) :: map()
  def circuit_breaker_config(service) do
    # First check application config, then fall back to constants
    case get([:circuit_breaker, service]) do
      nil -> WandererKills.Constants.circuit_breaker(service)
      config -> config
    end
  end

  @doc """
  Gets the application port number.
  """
  @spec port() :: pos_integer()
  def port, do: get(:port, 4004)

  @doc """
  Gets ESI API configuration.
  """
  @spec esi_config() :: map()
  def esi_config, do: get(:esi, %{})

  @doc """
  Gets zKillboard API configuration.
  """
  @spec zkb_config() :: map()
  def zkb_config, do: get(:zkb, %{})

  @doc """
  Gets parser configuration.
  """
  @spec parser_config() :: map()
  def parser_config, do: get(:parser, %{})

  @doc """
  Gets enricher configuration.
  """
  @spec enricher_config() :: map()
  def enricher_config, do: get(:enricher, %{})

  @doc """
  Gets telemetry configuration.
  """
  @spec telemetry_config() :: map()
  def telemetry_config, do: get(:telemetry, %{})

  @doc """
  Gets clock configuration for testing.
  """
  @spec clock() :: term()
  def clock, do: get(:clock)

  @doc """
  Gets cache configuration - returns entire cache config map.
  """
  @spec cache() :: map()
  def cache, do: get(:cache, %{})

  @doc """
  Gets cache configuration for a specific cache type and key.

  ## Parameters
  - `cache_type` - Type of cache (:killmails, :system, :esi)
  - `key` - Configuration key (:ttl, etc.)
  """
  @spec cache(atom(), atom()) :: term()
  def cache(cache_type, key) do
    get([:cache, cache_type, key])
  end

  @doc """
  Gets the recent fetch threshold for systems.
  """
  @spec recent_fetch_threshold() :: pos_integer()
  def recent_fetch_threshold do
    get(:cache_system_recent_fetch_threshold, WandererKills.Constants.threshold(:recent_fetch))
  end

  @doc """
  Gets killmail store configuration.
  """
  @spec killmail_store() :: map()
  def killmail_store, do: get(:killmail_store, %{})

  @doc """
  Gets parser configuration (alias for parser_config).
  """
  @spec parser() :: map()
  def parser, do: parser_config()

  @doc """
  Gets enricher configuration (alias for enricher_config).
  """
  @spec enricher() :: map()
  def enricher, do: enricher_config()

  @doc """
  Gets ESI configuration (alias for esi_config).
  """
  @spec esi() :: map()
  def esi, do: esi_config()

  # Private helper function for nested key access
  defp get_nested(nil, _keys, default), do: default
  defp get_nested(value, [], _default), do: value

  defp get_nested(value, [key | rest], default) when is_map(value) do
    case Map.get(value, key) do
      nil -> default
      next_value -> get_nested(next_value, rest, default)
    end
  end

  defp get_nested(_value, _keys, default), do: default
end
