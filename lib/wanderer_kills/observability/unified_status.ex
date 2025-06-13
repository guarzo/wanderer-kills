defmodule WandererKills.Observability.UnifiedStatus do
  @moduledoc """
  Unified status reporter that consolidates metrics from all system components
  into a single comprehensive status report.

  Provides a 5-minute summary that includes:
  - API call statistics (zkillboard and ESI)
  - Killmail processing metrics
  - WebSocket activity
  - Storage and cache performance
  - System resource usage
  - Preload activity
  """

  use GenServer
  require Logger

  alias WandererKills.Observability.{
    ApiTracker,
    WebSocketStats,
    Monitoring
  }

  alias WandererKills.RateLimiter

  @report_interval_ms :timer.minutes(5)

  # Client API

  @doc """
  Starts the unified status reporter.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generates and logs a status report immediately.
  """
  def report_now do
    GenServer.cast(__MODULE__, :report_now)
  end

  @doc """
  Gets the current status as a map.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    Logger.info("[UnifiedStatus] Starting unified status reporter")
    
    # Schedule first report
    interval = Keyword.get(opts, :interval_ms, @report_interval_ms)
    Process.send_after(self(), :generate_report, interval)

    state = %{
      interval_ms: interval,
      last_report_at: DateTime.utc_now(),
      enabled: Keyword.get(opts, :enabled, true)
    }

    Logger.info("[UnifiedStatus] Unified status reporter started successfully")
    {:ok, state}
  end

  @impl true
  def handle_info(:generate_report, state) do
    if state.enabled do
      do_generate_report(state)
    end

    # Schedule next report
    Process.send_after(self(), :generate_report, state.interval_ms)

    {:noreply, %{state | last_report_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_cast(:report_now, state) do
    do_generate_report(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = collect_all_metrics()
    {:reply, status, state}
  end

  # Private functions

  defp do_generate_report(state) do
    metrics = collect_all_metrics()

    # Calculate time since last report
    duration_minutes =
      (DateTime.diff(DateTime.utc_now(), state.last_report_at, :second) / 60)
      |> Float.round(1)

    # Format and log the report
    report = format_status_report(metrics, duration_minutes)

    # Log with structured data for parsing
    Logger.info(report,
      api_zkb_rpm: metrics.api.zkillboard.requests_per_minute,
      api_esi_rpm: metrics.api.esi.requests_per_minute,
      killmails_stored: metrics.processing.parser_stored,
      websocket_connections: metrics.websocket.connections_active,
      cache_hit_rate: metrics.cache.hit_rate,
      memory_mb: metrics.system.memory_mb
    )
  end

  defp collect_all_metrics do
    %{
      api: collect_api_metrics(),
      processing: collect_processing_metrics(),
      websocket: collect_websocket_metrics(),
      storage: collect_storage_metrics(),
      cache: collect_cache_metrics(),
      system: collect_system_metrics(),
      preload: collect_preload_metrics(),
      rate_limits: collect_rate_limit_status()
    }
  end

  defp collect_api_metrics do
    try do
      api_stats = ApiTracker.get_stats()

      %{
        zkillboard: api_stats.zkillboard,
        esi: api_stats.esi
      }
    rescue
      UndefinedFunctionError ->
        # ApiTracker module not loaded
        default_api_metrics()
    catch
      :exit, {:noproc, _} ->
        # ApiTracker not started yet
        default_api_metrics()
      :exit, {:timeout, _} ->
        # ApiTracker timeout
        default_api_metrics()
    end
  end
  
  defp default_api_metrics do
    %{
      zkillboard: %{
        requests_per_minute: 0,
        total_requests: 0,
        error_count: 0,
        avg_duration_ms: 0
      },
      esi: %{
        requests_per_minute: 0,
        total_requests: 0,
        error_count: 0,
        avg_duration_ms: 0
      }
    }
  end

  defp collect_processing_metrics do
    # Get RedisQ stats from ETS
    redisq_stats =
      case :ets.lookup(:wanderer_kills_stats, :redisq_stats) do
        [{:redisq_stats, stats}] -> stats
        [] -> %{kills_received: 0, kills_older: 0, kills_skipped: 0, active_systems: MapSet.new()}
      end

    # Get parser stats from telemetry events
    parser_stats =
      case :ets.lookup(:wanderer_kills_stats, :parser_stats) do
        [{:parser_stats, stats}] -> stats
        [] -> %{stored: 0, skipped: 0, failed: 0}
      end

    %{
      redisq_received: redisq_stats[:kills_received] || 0,
      redisq_older: redisq_stats[:kills_older] || 0,
      redisq_skipped: redisq_stats[:kills_skipped] || 0,
      redisq_systems: MapSet.size(redisq_stats[:active_systems] || MapSet.new()),
      parser_stored: parser_stats[:stored] || 0,
      parser_skipped: parser_stats[:skipped] || 0,
      parser_failed: parser_stats[:failed] || 0
    }
  end

  defp collect_websocket_metrics do
    case :ets.lookup(:wanderer_kills_stats, :websocket_stats) do
      [{:websocket_stats, stats}] ->
        %{
          connections_active: stats.connections.active,
          connections_total: stats.connections.total_connected,
          subscriptions_active: stats.subscriptions.active,
          subscriptions_systems: stats.subscriptions.total_systems,
          # Not currently tracked
          subscriptions_characters: 0,
          kills_sent_realtime: stats.kills_sent.realtime,
          kills_sent_preload: stats.kills_sent.preload,
          kills_sent_total: stats.kills_sent.total
        }

      [] ->
        # Fallback to WebSocketStats.get_stats() if ETS not available
        case WebSocketStats.get_stats() do
          {:ok, stats} ->
            %{
              connections_active: stats.connections.active,
              connections_total: stats.connections.total_connected,
              subscriptions_active: stats.subscriptions.active,
              subscriptions_systems: stats.subscriptions.total_systems,
              subscriptions_characters: 0,
              kills_sent_realtime: stats.kills_sent.realtime,
              kills_sent_preload: stats.kills_sent.preload,
              kills_sent_total: stats.kills_sent.total
            }

          _ ->
            default_websocket_metrics()
        end
    end
  end

  defp default_websocket_metrics do
    %{
      connections_active: 0,
      connections_total: 0,
      subscriptions_active: 0,
      subscriptions_systems: 0,
      subscriptions_characters: 0,
      kills_sent_realtime: 0,
      kills_sent_preload: 0,
      kills_sent_total: 0
    }
  end

  defp collect_storage_metrics do
    # Get ETS store statistics
    try do
      killmails_count = :ets.info(:killmails, :size) || 0
      systems_count = :ets.info(:system_killmails, :size) || 0

      # Estimate memory usage (rough calculation)
      # Approximate 200 bytes per killmail entry
      memory_mb = Float.round(killmails_count * 200 / (1024 * 1024), 1)

      %{
        killmails_count: killmails_count,
        systems_count: systems_count,
        memory_mb: memory_mb
      }
    catch
      _, _ ->
        %{
          killmails_count: 0,
          systems_count: 0,
          memory_mb: 0.0
        }
    end
  end

  defp collect_cache_metrics do
    # Get cache stats from Monitoring module which tracks Cachex
    case Monitoring.get_cache_stats(:wanderer_cache) do
      {:ok, stats} ->
        # Calculate hit rate if not present
        hit_rate =
          case stats do
            %{hit_rate: rate} when is_number(rate) ->
              rate

            %{hits: hits, misses: misses} when hits + misses > 0 ->
              Float.round(hits / (hits + misses) * 100, 1)

            _ ->
              0.0
          end

        miss_rate =
          case stats do
            %{miss_rate: rate} when is_number(rate) ->
              rate

            %{hits: hits, misses: misses} when hits + misses > 0 ->
              Float.round(misses / (hits + misses) * 100, 1)

            _ ->
              0.0
          end

        %{
          size: Map.get(stats, :size, 0),
          # Rough estimate
          memory_mb: Float.round(Map.get(stats, :size, 0) / 1024, 1),
          hit_rate: hit_rate,
          miss_rate: miss_rate,
          evictions: Map.get(stats, :evictions, 0),
          expirations: Map.get(stats, :expirations, 0)
        }

      _ ->
        %{
          size: 0,
          memory_mb: 0.0,
          hit_rate: 0.0,
          miss_rate: 0.0,
          evictions: 0,
          expirations: 0
        }
    end
  end

  defp collect_system_metrics do
    # Get system metrics directly
    memory_info = :erlang.memory()

    %{
      memory_mb: Float.round(memory_info[:total] / (1024 * 1024), 1),
      memory_binary_mb: Float.round(memory_info[:binary] / (1024 * 1024), 1),
      memory_processes_mb: Float.round(memory_info[:processes] / (1024 * 1024), 1),
      process_count: :erlang.system_info(:process_count),
      scheduler_usage: calculate_scheduler_usage()
    }
  end

  defp calculate_scheduler_usage do
    # This is a simple approximation - for real usage you'd need to track over time
    run_queue = :erlang.statistics(:run_queue)
    schedulers = :erlang.system_info(:schedulers)

    if schedulers > 0 do
      Float.round(run_queue / schedulers * 100, 1)
    else
      0.0
    end
  end

  defp collect_preload_metrics do
    # This would need to be implemented in HistoricalFetcher
    # For now, return placeholder data
    %{
      active_tasks: 0,
      completed_tasks: 0,
      failed_tasks: 0,
      total_delivered: 0
    }
  end

  defp collect_rate_limit_status do
    try do
      zkb_state = RateLimiter.get_bucket_state(:zkillboard)
      esi_state = RateLimiter.get_bucket_state(:esi)

      %{
        zkillboard: %{
          available: round(zkb_state.tokens),
          capacity: zkb_state.capacity
        },
        esi: %{
          available: round(esi_state.tokens),
          capacity: esi_state.capacity
        }
      }
    catch
      :exit, {:noproc, _} ->
        # RateLimiter not started yet
        default_rate_limit_status()
      :exit, {:timeout, _} ->
        # RateLimiter timeout
        default_rate_limit_status()
    end
  end
  
  defp default_rate_limit_status do
    %{
      zkillboard: %{
        available: 0,
        capacity: 10
      },
      esi: %{
        available: 0,
        capacity: 100
      }
    }
  end

  defp format_status_report(metrics, duration_minutes) do
    """

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    📊 WANDERER KILLS STATUS REPORT (#{duration_minutes}-minute summary)
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    🌐 API ACTIVITY:
       zkillboard: #{metrics.api.zkillboard.requests_per_minute} calls/min (#{metrics.api.zkillboard.total_requests} total) | Errors: #{metrics.api.zkillboard.error_count} | Avg: #{metrics.api.zkillboard.avg_duration_ms}ms
       ESI: #{metrics.api.esi.requests_per_minute} calls/min (#{metrics.api.esi.total_requests} total) | Errors: #{metrics.api.esi.error_count} | Avg: #{metrics.api.esi.avg_duration_ms}ms
       Rate Limits: ZKB #{metrics.rate_limits.zkillboard.available}/#{metrics.rate_limits.zkillboard.capacity} | ESI #{metrics.rate_limits.esi.available}/#{metrics.rate_limits.esi.capacity}

    🔄 KILLMAIL PROCESSING:
       RedisQ: #{metrics.processing.redisq_received} received | #{metrics.processing.redisq_older} older | #{metrics.processing.redisq_skipped} skipped | #{metrics.processing.redisq_systems} systems
       Parser: #{metrics.processing.parser_stored} stored | #{metrics.processing.parser_skipped} skipped | #{metrics.processing.parser_failed} failed

    🌐 WEBSOCKET ACTIVITY:
       Connections: #{metrics.websocket.connections_active} active | #{metrics.websocket.connections_total} total
       Subscriptions: #{metrics.websocket.subscriptions_active} active (#{metrics.websocket.subscriptions_systems} systems, #{metrics.websocket.subscriptions_characters} characters)
       Kills Delivered: #{metrics.websocket.kills_sent_total} (Realtime: #{metrics.websocket.kills_sent_realtime}, Preload: #{metrics.websocket.kills_sent_preload})

    💾 STORAGE & CACHE:
       Killmails: #{format_number(metrics.storage.killmails_count)} stored | #{metrics.storage.systems_count} unique systems
       Cache: #{format_number(metrics.cache.size)} entries | #{Float.round(metrics.cache.hit_rate, 1)}% hit rate | #{Float.round(metrics.cache.memory_mb, 1)} MB
       Memory: #{round(metrics.system.memory_mb)} MB total | #{round(metrics.system.memory_binary_mb)} MB binary | #{round(metrics.system.memory_processes_mb)} MB processes

    📦 PRELOAD ACTIVITY:
       Active Tasks: #{metrics.preload.active_tasks} | Completed: #{metrics.preload.completed_tasks} | Failed: #{metrics.preload.failed_tasks}
       Total Delivered: #{metrics.preload.total_delivered} kills

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """
  end

  defp format_number(num) when num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_number(num) when num >= 1_000 do
    "#{Float.round(num / 1_000, 1)}k"
  end

  defp format_number(num), do: to_string(num)
end
