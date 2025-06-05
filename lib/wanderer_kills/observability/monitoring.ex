defmodule WandererKills.Observability.Monitoring do
  @moduledoc """
  Unified monitoring and observability for the WandererKills application.

  This module consolidates health monitoring, metrics collection, telemetry measurements,
  and instrumentation functionality into a single observability interface.

  ## Features

  - Cache health monitoring and metrics collection
  - Application health status and uptime tracking
  - Telemetry measurements and periodic data gathering
  - Unified error handling and logging
  - Periodic health checks with configurable intervals
  - System metrics collection (memory, CPU, processes)

  ## Usage

  ```elixir
  # Start the monitoring GenServer
  {:ok, pid} = Monitoring.start_link([])

  # Check overall health
  {:ok, health} = Monitoring.check_health()

  # Get metrics
  {:ok, metrics} = Monitoring.get_metrics()

  # Get stats for a specific cache
  {:ok, stats} = Monitoring.get_cache_stats(:killmails_cache)

  # Telemetry measurements (called by TelemetryPoller)
  Monitoring.measure_http_requests()
  Monitoring.measure_cache_operations()
  Monitoring.measure_fetch_operations()
  ```

  ## Cache Names

  The following cache names are monitored:
  - `:killmails_cache` - Individual killmail data
  - `:system_cache` - System-level data and timestamps
  - `:esi_cache` - ESI API response cache
  """

  use GenServer
  require Logger
  alias WandererKills.Core.Clock

  @cache_names [:killmails_cache, :system_cache, :esi_cache]
  @health_check_interval :timer.minutes(5)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Performs a comprehensive health check of the application.

  Returns a map with health status for each cache and overall application status,
  including version, uptime, and timestamp information.

  ## Returns
  - `{:ok, health_map}` - Complete health status
  - `{:error, reason}` - If health check fails entirely

  ## Example

  ```elixir
  {:ok, health} = check_health()
  # %{
  #   healthy: true,
  #   timestamp: "2024-01-01T12:00:00Z",
  #   version: "1.0.0",
  #   uptime_seconds: 3600,
  #   caches: [
  #     %{name: :killmails_cache, healthy: true, status: "ok"},
  #     %{name: :system_cache, healthy: true, status: "ok"}
  #   ]
  # }
  ```
  """
  @spec check_health() :: {:ok, map()} | {:error, term()}
  def check_health do
    GenServer.call(__MODULE__, :check_health)
  end

  @doc """
  Gets comprehensive metrics for all monitored caches and application stats.

  Returns cache statistics and application metrics that can be used for
  monitoring, alerting, and performance analysis.

  ## Returns
  - `{:ok, metrics_map}` - Metrics for all caches and app stats
  - `{:error, reason}` - If metrics collection fails

  ## Example

  ```elixir
  {:ok, metrics} = get_metrics()
  # %{
  #   timestamp: "2024-01-01T12:00:00Z",
  #   uptime_seconds: 3600,
  #   caches: [
  #     %{name: :killmails_cache, size: 1000, hit_rate: 0.85, miss_rate: 0.15},
  #     %{name: :system_cache, size: 500, hit_rate: 0.92, miss_rate: 0.08}
  #   ]
  # }
  ```
  """
  @spec get_metrics() :: {:ok, map()} | {:error, term()}
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Get telemetry data for all monitored caches.

  This is an alias for `get_metrics/0` as telemetry and metrics
  are essentially the same data in this context.

  ## Returns
  - `{:ok, telemetry_map}` - Telemetry data for all caches
  - `{:error, reason}` - If telemetry collection fails
  """
  @spec get_telemetry() :: {:ok, map()} | {:error, term()}
  def get_telemetry do
    get_metrics()
  end

  @doc """
  Get statistics for a specific cache.

  ## Parameters
  - `cache_name` - The name of the cache to get stats for

  ## Returns
  - `{:ok, stats}` - Cache statistics map
  - `{:error, reason}` - If stats collection fails

  ## Example

  ```elixir
  {:ok, stats} = get_cache_stats(:killmails_cache)
  # %{hit_rate: 0.85, size: 1000, evictions: 10, ...}
  ```
  """
  @spec get_cache_stats(atom()) :: {:ok, map()} | {:error, term()}
  def get_cache_stats(cache_name) do
    GenServer.call(__MODULE__, {:get_cache_stats, cache_name})
  end

  # Telemetry measurement functions (called by TelemetryPoller)

  @doc """
  Measures HTTP request metrics for telemetry.

  This function is called by TelemetryPoller to emit HTTP request metrics.
  """
  @spec measure_http_requests() :: :ok
  def measure_http_requests do
    :telemetry.execute(
      [:wanderer_kills, :system, :http_requests],
      %{count: :erlang.statistics(:reductions) |> elem(0)},
      %{}
    )
  end

  @doc """
  Measures cache operation metrics for telemetry.

  This function is called by TelemetryPoller to emit cache operation metrics.
  """
  @spec measure_cache_operations() :: :ok
  def measure_cache_operations do
    cache_metrics =
      Enum.map(@cache_names, fn cache_name ->
        case Cachex.size(cache_name) do
          {:ok, size} -> size
          _ -> 0
        end
      end)
      |> Enum.sum()

    :telemetry.execute(
      [:wanderer_kills, :system, :cache_operations],
      %{total_cache_size: cache_metrics},
      %{}
    )
  end

  @doc """
  Measures fetch operation metrics for telemetry.

  This function is called by TelemetryPoller to emit fetch operation metrics.
  """
  @spec measure_fetch_operations() :: :ok
  def measure_fetch_operations do
    process_count = :erlang.system_info(:process_count)

    :telemetry.execute(
      [:wanderer_kills, :system, :fetch_operations],
      %{process_count: process_count},
      %{}
    )
  end

  @doc """
  Measures system resource metrics for telemetry.

  This function emits comprehensive system metrics including memory and CPU usage.
  """
  @spec measure_system_resources() :: :ok
  def measure_system_resources do
    memory_info = :erlang.memory()

    :telemetry.execute(
      [:wanderer_kills, :system, :memory],
      %{
        total_memory: memory_info[:total],
        process_memory: memory_info[:processes],
        atom_memory: memory_info[:atom],
        binary_memory: memory_info[:binary]
      },
      %{}
    )

    # Process and scheduler metrics
    :telemetry.execute(
      [:wanderer_kills, :system, :cpu],
      %{
        process_count: :erlang.system_info(:process_count),
        port_count: :erlang.system_info(:port_count),
        schedulers: :erlang.system_info(:schedulers),
        run_queue: :erlang.statistics(:run_queue)
      },
      %{}
    )
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("[Monitoring] Starting unified monitoring with periodic health checks")

    # Start periodic health checks if not disabled in opts
    if !Keyword.get(opts, :disable_periodic_checks, false) do
      schedule_health_check()
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call(:check_health, _from, state) do
    health = build_comprehensive_health_status()
    {:reply, {:ok, health}, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = build_comprehensive_metrics()
    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_call({:get_cache_stats, cache_name}, _from, state) do
    stats = get_cache_stats_internal(cache_name)
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:check_health, state) do
    Logger.debug("[Monitoring] Running periodic health check")
    _health = build_comprehensive_health_status()
    schedule_health_check()
    {:noreply, state}
  end

  # Private helper functions

  defp schedule_health_check do
    Process.send_after(self(), :check_health, @health_check_interval)
  end

  @spec build_comprehensive_health_status() :: map()
  defp build_comprehensive_health_status do
    cache_checks = Enum.map(@cache_names, &build_cache_health_check/1)
    all_healthy = Enum.all?(cache_checks, & &1.healthy)

    %{
      healthy: all_healthy,
      timestamp: Clock.now_iso8601(),
      version: get_app_version(),
      uptime_seconds: get_uptime_seconds(),
      caches: cache_checks,
      system: get_system_info()
    }
  end

  @spec build_comprehensive_metrics() :: map()
  defp build_comprehensive_metrics do
    cache_metrics = Enum.map(@cache_names, &build_cache_metrics/1)

    %{
      timestamp: Clock.now_iso8601(),
      uptime_seconds: get_uptime_seconds(),
      caches: cache_metrics,
      system: get_system_info(),
      aggregate: %{
        total_cache_size: Enum.sum(Enum.map(cache_metrics, &Map.get(&1, :size, 0))),
        average_hit_rate: calculate_average_hit_rate(cache_metrics)
      }
    }
  end

  @spec build_cache_health_check(atom()) :: map()
  defp build_cache_health_check(cache_name) do
    try do
      case Cachex.size(cache_name) do
        {:ok, _size} ->
          %{name: cache_name, healthy: true, status: "ok"}

        {:error, reason} ->
          Logger.error(
            "[Monitoring] Cache health check failed for #{cache_name}: #{inspect(reason)}"
          )

          %{name: cache_name, healthy: false, status: "error", reason: inspect(reason)}
      end
    rescue
      error ->
        Logger.error(
          "[Monitoring] Cache health check exception for #{cache_name}: #{inspect(error)}"
        )

        %{name: cache_name, healthy: false, status: "unavailable"}
    end
  end

  @spec build_cache_metrics(atom()) :: map()
  defp build_cache_metrics(cache_name) do
    case Cachex.stats(cache_name) do
      {:ok, stats} ->
        %{
          name: cache_name,
          size: Map.get(stats, :size, 0),
          hit_rate: Map.get(stats, :hit_rate, 0.0),
          miss_rate: Map.get(stats, :miss_rate, 0.0),
          evictions: Map.get(stats, :evictions, 0),
          operations: Map.get(stats, :operations, 0),
          memory: Map.get(stats, :memory, 0)
        }

      {:error, reason} ->
        Logger.error(
          "[Monitoring] Cache metrics collection failed for #{cache_name}: #{inspect(reason)}"
        )

        %{name: cache_name, error: "Unable to retrieve stats", reason: inspect(reason)}
    end
  end

  @spec get_cache_stats_internal(atom()) :: {:ok, map()} | {:error, term()}
  defp get_cache_stats_internal(cache_name) do
    case Cachex.stats(cache_name) do
      {:ok, stats} -> {:ok, stats}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_system_info() :: map()
  defp get_system_info do
    try do
      memory_info = :erlang.memory()

      %{
        memory: %{
          total: memory_info[:total],
          processes: memory_info[:processes],
          atom: memory_info[:atom],
          binary: memory_info[:binary]
        },
        processes: %{
          count: :erlang.system_info(:process_count),
          limit: :erlang.system_info(:process_limit)
        },
        ports: %{
          count: :erlang.system_info(:port_count),
          limit: :erlang.system_info(:port_limit)
        },
        schedulers: :erlang.system_info(:schedulers),
        run_queue: :erlang.statistics(:run_queue),
        ets_tables: length(:ets.all())
      }
    rescue
      error ->
        Logger.warning("Failed to collect system info: #{inspect(error)}")
        %{error: "System info collection failed"}
    end
  end

  @spec calculate_average_hit_rate([map()]) :: float()
  defp calculate_average_hit_rate(cache_metrics) do
    valid_metrics = Enum.reject(cache_metrics, &Map.has_key?(&1, :error))

    case valid_metrics do
      [] ->
        0.0

      metrics ->
        hit_rates = Enum.map(metrics, &Map.get(&1, :hit_rate, 0.0))
        Enum.sum(hit_rates) / length(hit_rates)
    end
  end

  defp get_app_version do
    Application.spec(:wanderer_kills, :vsn)
    |> to_string()
  rescue
    _ -> "unknown"
  end

  defp get_uptime_seconds do
    :erlang.statistics(:wall_clock)
    |> elem(0)
    |> div(1000)
  end
end
