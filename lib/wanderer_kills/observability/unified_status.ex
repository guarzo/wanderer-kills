defmodule WandererKills.Observability.UnifiedStatus do
  @moduledoc """
  Periodically aggregates metrics from *all* Wanderer Kills subsystems
  (API, pipeline, WebSocket, cache, etc.) into a single structured snapshot
  and logs an easy-to-read banner every `@report_interval_ms`.

      iex> WandererKills.Observability.UnifiedStatus.report_now()
      :ok
  """

  use GenServer
  require Logger

  alias WandererKills.Observability.{ApiTracker, WebSocketStats, Monitoring}
  alias WandererKills.RateLimiter

  @report_interval_ms 5 * 60 * 1_000

  @default_api_metrics %{
    requests_per_minute: 0,
    total_requests: 0,
    error_count: 0,
    avg_duration_ms: 0
  }

  @typedoc "Internal server state"
  @type state :: %__MODULE__{
          interval_ms: pos_integer(),
          last_report_at: DateTime.t()
        }
  defstruct interval_ms: @report_interval_ms, last_report_at: DateTime.utc_now()

  # ────────────────────────────  Public API  ────────────────────────────

  @spec start_link(GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec report_now() :: :ok
  def report_now, do: GenServer.cast(__MODULE__, :report_now)

  @spec get_status() :: map()
  def get_status, do: GenServer.call(__MODULE__, :get_status)

  # ────────────────────────────  GenServer  ─────────────────────────────

  @impl GenServer
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @report_interval_ms)
    {:ok, %__MODULE__{interval_ms: interval}, {:continue, :schedule_report}}
  end

  @impl GenServer
  def handle_continue(:schedule_report, %__MODULE__{interval_ms: interval} = st) do
    schedule_next_report(interval)
    Logger.info("[UnifiedStatus] started (interval: #{interval / 1_000}s)")
    {:noreply, st}
  end

  @impl GenServer
  def handle_info(:generate_report, %__MODULE__{} = st) do
    generate_and_log_report(st)
    schedule_next_report(st.interval_ms)
    {:noreply, %{st | last_report_at: DateTime.utc_now()}}
  end

  @impl GenServer
  def handle_cast(:report_now, %__MODULE__{} = st) do
    generate_and_log_report(st)
    {:noreply, st}
  end

  @impl GenServer
  def handle_call(:get_status, _from, %__MODULE__{} = st) do
    {:reply, collect_all_metrics(), st}
  end

  # ────────────────────────────  Internals  ─────────────────────────────

  ## Scheduling

  defp schedule_next_report(interval_ms),
    do: Process.send_after(self(), :generate_report, interval_ms)

  ## Report generation

  defp generate_and_log_report(%__MODULE__{last_report_at: last} = _st) do
    metrics = collect_all_metrics()
    summary_mins = Float.round(DateTime.diff(DateTime.utc_now(), last, :second) / 60, 1)

    Logger.info(format_status_report(metrics, summary_mins), log_metadata(metrics))
  end

  defp log_metadata(metrics) do
    [
      api_zkb_rpm: get_in(metrics, [:api, :zkillboard, :requests_per_minute]),
      api_esi_rpm: get_in(metrics, [:api, :esi, :requests_per_minute]),
      killmails_stored: get_in(metrics, [:processing, :parser_stored]),
      websocket_connections: get_in(metrics, [:websocket, :connections_active]),
      cache_hit_rate: get_in(metrics, [:cache, :hit_rate]),
      memory_mb: get_in(metrics, [:system, :memory_mb])
    ]
  end

  ## Master collector

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

  # ────────────────────────────  Collectors  ────────────────────────────

  ### API

  defp collect_api_metrics do
    api_stats =
      safe_apply(ApiTracker, :get_stats, [], %{zkillboard: %{}, esi: %{}})

    %{
      zkillboard: Map.merge(@default_api_metrics, Map.get(api_stats, :zkillboard, %{})),
      esi: Map.merge(@default_api_metrics, Map.get(api_stats, :esi, %{}))
    }
  end

  ### Processing

  defp collect_processing_metrics do
    redisq_stats = ets_get(:wanderer_kills_stats, :redisq_stats, %{})
    parser_stats = ets_get(:wanderer_kills_stats, :parser_stats, %{})

    %{
      redisq_received: Map.get(redisq_stats, :kills_received, 0),
      redisq_older: Map.get(redisq_stats, :kills_older, 0),
      redisq_skipped: Map.get(redisq_stats, :kills_skipped, 0),
      redisq_systems: redisq_stats |> Map.get(:active_systems, MapSet.new()) |> MapSet.size(),
      parser_stored: Map.get(parser_stats, :stored, 0),
      parser_skipped: Map.get(parser_stats, :skipped, 0),
      parser_failed: Map.get(parser_stats, :failed, 0)
    }
  end

  ### WebSocket

  defp collect_websocket_metrics do
    stats =
      ets_get(:wanderer_kills_stats, :websocket_stats, nil) ||
        safe_apply(WebSocketStats, :get_stats, [], :unavailable)

    case stats do
      {:ok, s} -> format_ws_metrics(s)
      %{connections: _} = s -> format_ws_metrics(s)
      _ -> default_websocket_metrics()
    end
  end

  defp format_ws_metrics(stats) do
    %{
      connections_active: get_in(stats, [:connections, :active]) || 0,
      connections_total: get_in(stats, [:connections, :total_connected]) || 0,
      subscriptions_active: get_in(stats, [:subscriptions, :active]) || 0,
      subscriptions_systems: get_in(stats, [:subscriptions, :total_systems]) || 0,
      subscriptions_characters: get_in(stats, [:subscriptions, :total_characters]) || 0,
      kills_sent_realtime: get_in(stats, [:kills_sent, :realtime]) || 0,
      kills_sent_preload: get_in(stats, [:kills_sent, :preload]) || 0,
      kills_sent_total: get_in(stats, [:kills_sent, :total]) || 0
    }
  end

  defp default_websocket_metrics, do: format_ws_metrics(%{})

  ### Storage

  defp collect_storage_metrics do
    killmails = safe_ets_info(:killmails, :size)
    systems = safe_ets_info(:system_killmails, :size)

    %{
      killmails_count: killmails,
      systems_count: systems,
      # crude but cheap – 200B/killmail
      memory_mb: Float.round(killmails * 200 / 1_048_576, 1)
    }
  end

  ### Cache

  defp collect_cache_metrics do
    case safe_apply(Monitoring, :get_cache_stats, [:wanderer_cache], :unavailable) do
      {:ok, stats} ->
        hits = Map.get(stats, :hits, 0)
        misses = Map.get(stats, :misses, 0)

        %{
          size: Map.get(stats, :size, 0),
          memory_mb: Float.round(Map.get(stats, :size, 0) / 1024, 1),
          hit_rate: hit_rate(hits, misses),
          miss_rate: hit_rate(misses, hits),
          evictions: Map.get(stats, :evictions, 0),
          expirations: Map.get(stats, :expirations, 0)
        }

      _ ->
        %{size: 0, memory_mb: 0.0, hit_rate: 0.0, miss_rate: 0.0, evictions: 0, expirations: 0}
    end
  end

  ### System

  defp collect_system_metrics do
    m = :erlang.memory()

    %{
      memory_mb: Float.round(m[:total] / 1_048_576, 1),
      memory_binary_mb: Float.round(m[:binary] / 1_048_576, 1),
      memory_processes_mb: Float.round(m[:processes] / 1_048_576, 1),
      process_count: :erlang.system_info(:process_count),
      scheduler_usage: scheduler_usage()
    }
  end

  defp scheduler_usage do
    schedulers = :erlang.system_info(:schedulers) |> max(1)
    queue = :erlang.statistics(:run_queue)

    Float.round(queue / schedulers * 100, 1)
  end

  ### Preload (placeholder)

  defp collect_preload_metrics do
    %{
      active_tasks: 0,
      completed_tasks: 0,
      failed_tasks: 0,
      total_delivered: 0
    }
  end

  ### Rate limits

  defp collect_rate_limit_status do
    %{
      zkillboard:
        format_bucket(safe_apply(RateLimiter, :get_bucket_state, [:zkillboard], :na), 10),
      esi: format_bucket(safe_apply(RateLimiter, :get_bucket_state, [:esi], :na), 100)
    }
  end

  defp format_bucket(%{tokens: t, capacity: c}, _), do: %{available: round(t), capacity: c}
  defp format_bucket(:na, capacity), do: %{available: 0, capacity: capacity}

  # ────────────────────────────  Utilities  ─────────────────────────────

  defp safe_apply(mod, fun, args, default) do
    cond do
      not Code.ensure_loaded?(mod) ->
        default

      not function_exported?(mod, fun, length(args)) ->
        default

      true ->
        try do
          apply(mod, fun, args)
        catch
          _, _ -> default
        end
    end
  end

  defp ets_get(tab, key, default) do
    case :ets.lookup(tab, key) do
      [{^key, val}] -> val
      _ -> default
    end
  end

  defp safe_ets_info(tab, field) do
    try do
      case :ets.info(tab, field) do
        :undefined -> 0
        n when is_integer(n) -> n
        _ -> 0
      end
    rescue
      _ -> 0
    end
  end

  defp hit_rate(part, whole) do
    total = part + whole
    if total > 0, do: Float.round(part / total * 100, 1), else: 0.0
  end

  ## Pretty banner builder

  defp format_status_report(m, mins) do
    """
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            📊  WANDERER KILLS STATUS (#{mins} min)
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    🌐 API
        zkillboard  #{m.api.zkillboard.requests_per_minute} rpm  \
    (total #{m.api.zkillboard.total_requests})  •  \
    errors #{m.api.zkillboard.error_count}  •  \
    avg #{m.api.zkillboard.avg_duration_ms} ms
        ESI          #{m.api.esi.requests_per_minute} rpm  \
    (total #{m.api.esi.total_requests})  •  \
    errors #{m.api.esi.error_count}  •  \
    avg #{m.api.esi.avg_duration_ms} ms
        limits       ZKB #{m.rate_limits.zkillboard.available}/#{m.rate_limits.zkillboard.capacity}  |  \
    ESI #{m.rate_limits.esi.available}/#{m.rate_limits.esi.capacity}

    🔄 Processing
        RedisQ       #{m.processing.redisq_received} recv, \
    #{m.processing.redisq_older} old, \
    #{m.processing.redisq_skipped} skipped  •  \
    #{m.processing.redisq_systems} systems
        Parser       #{m.processing.parser_stored} stored  •  \
    #{m.processing.parser_skipped} skipped  •  \
    #{m.processing.parser_failed} failed

    🌐 WebSocket
        Connections  #{m.websocket.connections_active} active / #{m.websocket.connections_total} total
        Subs         #{m.websocket.subscriptions_active} active  \
    (#{m.websocket.subscriptions_systems} systems, \
    #{m.websocket.subscriptions_characters} chars)
        Kills sent   #{m.websocket.kills_sent_total}  \
    (#{m.websocket.kills_sent_realtime} real-time, \
    #{m.websocket.kills_sent_preload} preload)

    💾 Storage / Cache
        Killmails    #{format_number(m.storage.killmails_count)}  •  \
    #{m.storage.systems_count} systems  •  \
    ≈#{m.storage.memory_mb} MB
        Cache        #{format_number(m.cache.size)} entries  •  \
    #{m.cache.hit_rate}% hit  •  \
    #{m.cache.memory_mb} MB

    🖥  System
        Memory       #{m.system.memory_mb} MB (bin #{m.system.memory_binary_mb} / proc #{m.system.memory_processes_mb})
        Processes    #{m.system.process_count}
        SchedulerQ   #{m.system.scheduler_usage}%

    📦 Preload       #{m.preload.active_tasks} active  •  \
    #{m.preload.completed_tasks} done  •  \
    #{m.preload.failed_tasks} failed  •  \
    #{m.preload.total_delivered} kills delivered
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """
  end

  defp format_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)} M"
  defp format_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)} k"
  defp format_number(n), do: Integer.to_string(n)
end
