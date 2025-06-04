defmodule WandererKills.Config do
  @moduledoc """
  Centralized configuration module for WandererKills application.

  This module provides typed getters for configuration values, ensuring
  default values are applied consistently and eliminating spread-out
  compile_env and get_env calls throughout the codebase.

  ## Usage

  ```elixir
  # Get cache configuration
  cache_config = Config.cache()
  killmail_config = Config.cache(:killmails)

  # Get HTTP client configuration
  client_config = Config.http_client()

  # Get ESI configuration
  esi_config = Config.esi()
  ```
  """

  @type cache_type :: :killmails | :system | :esi
  @type cache_config :: %{name: atom(), ttl: pos_integer()}
  @type http_config :: %{
          timeout: pos_integer(),
          recv_timeout: pos_integer(),
          max_redirects: non_neg_integer(),
          user_agent: String.t()
        }

  @doc """
  Gets the complete cache configuration.

  ## Returns
  A map containing all cache configurations.
  """
  @spec cache() :: %{cache_type() => cache_config()}
  def cache do
    Application.get_env(:wanderer_kills, :cache, %{
      killmails: [name: :killmails_cache, ttl: :timer.hours(24)],
      system: [name: :system_cache, ttl: :timer.hours(1)],
      esi: [name: :esi_cache, ttl: :timer.hours(48)]
    })
  end

  @doc """
  Gets cache configuration for a specific cache type.

  ## Parameters
  - `cache_type` - The type of cache (:killmails, :system, or :esi)

  ## Returns
  A map containing:
  - `:name` - The cache name
  - `:ttl` - The TTL in milliseconds
  """
  @spec cache(cache_type()) :: cache_config()
  def cache(cache_type) do
    config = cache()[cache_type]

    %{
      name: Keyword.get(config, :name),
      ttl: Keyword.get(config, :ttl, :timer.hours(24))
    }
  end

  @doc """
  Gets HTTP client configuration.

  ## Returns
  HTTP client configuration map.
  """
  @spec http_client() :: http_config()
  def http_client do
    config = Application.get_env(:wanderer_kills, :http_client, [])

    %{
      timeout: Keyword.get(config, :timeout, :timer.seconds(30)),
      recv_timeout: Keyword.get(config, :recv_timeout, :timer.seconds(60)),
      max_redirects: Keyword.get(config, :max_redirects, 3),
      user_agent: Keyword.get(config, :user_agent, "WandererKills/1.0")
    }
  end

  @doc """
  Gets ESI API configuration.

  ## Returns
  ESI configuration map.
  """
  @spec esi() :: %{base_url: String.t(), timeout: pos_integer(), rate_limit: pos_integer()}
  def esi do
    config = Application.get_env(:wanderer_kills, :esi, [])

    case config do
      config when is_map(config) ->
        %{
          base_url: Map.get(config, :base_url, "https://esi.evetech.net"),
          timeout: Map.get(config, :timeout, :timer.seconds(30)),
          rate_limit: Map.get(config, :rate_limit, 150)
        }

      config when is_list(config) ->
        %{
          base_url: Keyword.get(config, :base_url, "https://esi.evetech.net"),
          timeout: Keyword.get(config, :timeout, :timer.seconds(30)),
          rate_limit: Keyword.get(config, :rate_limit, 150)
        }
    end
  end

  @doc """
  Gets database configuration.

  ## Returns
  Database configuration map.
  """
  @spec database() :: %{
          pool_size: pos_integer(),
          timeout: pos_integer(),
          queue_timeout: pos_integer()
        }
  def database do
    config = Application.get_env(:wanderer_kills, :database, [])

    %{
      pool_size: Keyword.get(config, :pool_size, 10),
      timeout: Keyword.get(config, :timeout, :timer.seconds(15)),
      queue_timeout: Keyword.get(config, :queue_timeout, :timer.seconds(5))
    }
  end

  @doc """
  Gets recent fetch threshold for system cache operations.

  ## Returns
  Recent fetch threshold in milliseconds.
  """
  @spec recent_fetch_threshold() :: pos_integer()
  def recent_fetch_threshold do
    Application.get_env(:wanderer_kills, :recent_fetch_threshold_ms, :timer.minutes(5))
  end

  @doc """
  Gets concurrency configuration for batch processing.

  ## Returns
  Concurrency configuration map.
  """
  @spec concurrency() :: %{
          max_concurrent: pos_integer(),
          batch_size: pos_integer(),
          timeout_ms: pos_integer()
        }
  def concurrency do
    config = Application.get_env(:wanderer_kills, :concurrency, [])

    case config do
      config when is_map(config) ->
        %{
          max_concurrent: Map.get(config, :max_concurrent, 10),
          batch_size: Map.get(config, :batch_size, 50),
          timeout_ms: Map.get(config, :timeout_ms, 30_000)
        }

      config when is_list(config) ->
        %{
          max_concurrent: Keyword.get(config, :max_concurrent, 10),
          batch_size: Keyword.get(config, :batch_size, 50),
          timeout_ms: Keyword.get(config, :timeout_ms, 30_000)
        }
    end
  end

  @doc """
  Gets clock configuration for testing and time mocking.
  """
  @spec clock() :: term()
  def clock do
    Application.get_env(:wanderer_kills, :clock)
  end

  @doc """
  Gets parser configuration settings.
  """
  @spec parser() :: %{cutoff_seconds: integer(), summary_interval_ms: integer()}
  def parser do
    config = Application.get_env(:wanderer_kills, :parser, [])

    case config do
      config when is_map(config) ->
        %{
          cutoff_seconds: Map.get(config, :cutoff_seconds, 3_600),
          summary_interval_ms: Map.get(config, :summary_interval_ms, 60_000)
        }

      config when is_list(config) ->
        %{
          cutoff_seconds: Keyword.get(config, :cutoff_seconds, 3_600),
          summary_interval_ms: Keyword.get(config, :summary_interval_ms, 60_000)
        }
    end
  end

  @doc """
  Gets retry configuration settings.
  """
  @spec retry() :: %{max_retries: integer(), base_backoff: integer(), max_backoff: integer()}
  def retry do
    config = Application.get_env(:wanderer_kills, :retry, [])

    case config do
      config when is_map(config) ->
        %{
          max_retries: Map.get(config, :max_retries, 3),
          base_backoff: Map.get(config, :base_backoff, 1_000),
          max_backoff: Map.get(config, :max_backoff, 30_000)
        }

      config when is_list(config) ->
        %{
          max_retries: Keyword.get(config, :max_retries, 3),
          base_backoff: Keyword.get(config, :base_backoff, 1_000),
          max_backoff: Keyword.get(config, :max_backoff, 30_000)
        }
    end
  end

  @doc """
  Gets enricher configuration settings.
  """
  @spec enricher() :: %{
          max_concurrency: integer(),
          task_timeout_ms: integer(),
          min_attackers_for_parallel: integer()
        }
  def enricher do
    config = Application.get_env(:wanderer_kills, :enricher, [])

    case config do
      config when is_map(config) ->
        %{
          max_concurrency: Map.get(config, :max_concurrency, 10),
          task_timeout_ms: Map.get(config, :task_timeout_ms, 30_000),
          min_attackers_for_parallel: Map.get(config, :min_attackers_for_parallel, 3)
        }

      config when is_list(config) ->
        %{
          max_concurrency: Keyword.get(config, :max_concurrency, 10),
          task_timeout_ms: Keyword.get(config, :task_timeout_ms, 30_000),
          min_attackers_for_parallel: Keyword.get(config, :min_attackers_for_parallel, 3)
        }
    end
  end
end
