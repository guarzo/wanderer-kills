defmodule WandererKills.Observability.WebSocketStats do
  @moduledoc """
  Dedicated GenServer for tracking WebSocket connection and message statistics.

  This module consolidates WebSocket statistics tracking that was previously
  scattered across the channel implementation. It provides:

  - Connection metrics (active connections, total connections)
  - Message metrics (kills sent, preload counts, realtime counts)
  - Subscription metrics (active subscriptions, system counts)
  - Performance metrics (message rates, connection duration)

  ## Usage

  ```elixir
  # Track a kill sent to websocket client
  WebSocketStats.increment_kills_sent(:realtime)
  WebSocketStats.increment_kills_sent(:preload, 5)

  # Track connection events
  WebSocketStats.track_connection(:connected)
  WebSocketStats.track_connection(:disconnected)

  # Get current statistics
  {:ok, stats} = WebSocketStats.get_stats()

  # Reset statistics
  WebSocketStats.reset_stats()
  ```

  ## Telemetry Events

  The module emits telemetry events for external monitoring:
  - `[:wanderer_kills, :websocket, :kills_sent]` - When kills are sent to clients
  - `[:wanderer_kills, :websocket, :connection]` - When connections change
  - `[:wanderer_kills, :websocket, :subscription]` - When subscriptions change
  """

  use GenServer
  require Logger
  alias WandererKills.Support.Clock
  alias WandererKills.Observability.LogFormatter

  @stats_summary_interval :timer.minutes(5)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Increments the count of kills sent to WebSocket clients.

  ## Parameters
  - `type` - Either `:realtime` or `:preload`
  - `count` - Number of kills sent (default: 1)
  """
  @spec increment_kills_sent(:realtime | :preload, pos_integer()) :: :ok
  def increment_kills_sent(type, count \\ 1)
      when type in [:realtime, :preload] and is_integer(count) and count > 0 do
    WandererKills.Observability.Telemetry.websocket_kills_sent(type, count)
    GenServer.cast(__MODULE__, {:increment_kills_sent, type, count})
  end

  @doc """
  Tracks WebSocket connection events.

  ## Parameters
  - `event` - Either `:connected` or `:disconnected`
  - `metadata` - Optional metadata map with connection details
  """
  @spec track_connection(:connected | :disconnected, map()) :: :ok
  def track_connection(event, metadata \\ %{})
      when event in [:connected, :disconnected] do
    WandererKills.Observability.Telemetry.websocket_connection(event, metadata)
    GenServer.cast(__MODULE__, {:track_connection, event, metadata})
  end

  @doc """
  Tracks WebSocket subscription changes.

  ## Parameters
  - `event` - Either `:added`, `:updated`, or `:removed`
  - `system_count` - Number of systems in the subscription
  - `metadata` - Optional metadata map
  """
  @spec track_subscription(:added | :updated | :removed, non_neg_integer(), map()) :: :ok
  def track_subscription(event, system_count, metadata \\ %{})
      when event in [:added, :updated, :removed] and is_integer(system_count) do
    WandererKills.Observability.Telemetry.websocket_subscription(event, system_count, metadata)
    GenServer.cast(__MODULE__, {:track_subscription, event, system_count})
  end

  @doc """
  Gets current WebSocket statistics.

  ## Returns
  - `{:ok, stats_map}` - Complete statistics
  - `{:error, reason}` - If stats collection fails
  """
  @spec get_stats() :: {:ok, map()} | {:error, term()}
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Resets all WebSocket statistics counters.
  """
  @spec reset_stats() :: :ok
  def reset_stats do
    GenServer.call(__MODULE__, :reset_stats)
  end

  @doc """
  Gets active connection count from the registry.
  """
  @spec get_active_connections() :: non_neg_integer()
  def get_active_connections do
    GenServer.call(__MODULE__, :get_active_connections)
  end

  @doc """
  Gets telemetry measurements for WebSocket metrics.

  This function is called by TelemetryPoller to emit WebSocket metrics.
  """
  @spec measure_websocket_metrics() :: :ok
  def measure_websocket_metrics do
    case get_stats() do
      {:ok, stats} ->
        :telemetry.execute(
          [:wanderer_kills, :system, :websocket_metrics],
          %{
            active_connections: stats.connections.active,
            total_kills_sent: stats.kills_sent.total,
            kills_sent_rate: calculate_rate(stats)
          },
          %{}
        )

      {:error, reason} ->
        LogFormatter.format_error("WebSocket", "metrics_failed", %{}, inspect(reason))
        |> Logger.warning()
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("[WebSocketStats] Starting WebSocket statistics tracking")

    # Schedule periodic stats summary
    if !Keyword.get(opts, :disable_periodic_summary, false) do
      schedule_stats_summary()
    end

    state = %{
      kills_sent: %{
        realtime: 0,
        preload: 0
      },
      connections: %{
        total_connected: 0,
        total_disconnected: 0,
        active: 0
      },
      subscriptions: %{
        total_added: 0,
        total_removed: 0,
        active: 0,
        total_systems: 0
      },
      rates: %{
        last_measured: DateTime.utc_now(),
        kills_per_minute: 0.0,
        connections_per_minute: 0.0
      },
      started_at: DateTime.utc_now(),
      last_reset: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = build_stats_response(state)
    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    new_state = %{state | kills_sent: %{realtime: 0, preload: 0}, last_reset: DateTime.utc_now()}
    Logger.info("[WebSocketStats] Statistics reset")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_active_connections, _from, state) do
    # Try to get count from registry, fallback to internal counter
    count =
      try do
        Registry.count(WandererKills.Registry)
      rescue
        _ -> state.connections.active
      end

    {:reply, count, state}
  end

  @impl true
  def handle_cast({:increment_kills_sent, type, count}, state) do
    new_kills_sent = Map.update!(state.kills_sent, type, &(&1 + count))
    new_state = %{state | kills_sent: new_kills_sent}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:track_connection, :connected, _metadata}, state) do
    new_connections = %{
      state.connections
      | total_connected: state.connections.total_connected + 1,
        active: state.connections.active + 1
    }

    new_state = %{state | connections: new_connections}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:track_connection, :disconnected, _metadata}, state) do
    new_connections = %{
      state.connections
      | total_disconnected: state.connections.total_disconnected + 1,
        active: max(0, state.connections.active - 1)
    }

    new_state = %{state | connections: new_connections}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:track_subscription, :added, system_count}, state) do
    new_subscriptions = %{
      state.subscriptions
      | total_added: state.subscriptions.total_added + 1,
        active: state.subscriptions.active + 1,
        total_systems: state.subscriptions.total_systems + system_count
    }

    new_state = %{state | subscriptions: new_subscriptions}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:track_subscription, :removed, system_count}, state) do
    new_subscriptions = %{
      state.subscriptions
      | total_removed: state.subscriptions.total_removed + 1,
        active: max(0, state.subscriptions.active - 1),
        total_systems: max(0, state.subscriptions.total_systems - system_count)
    }

    new_state = %{state | subscriptions: new_subscriptions}
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:track_subscription, :updated, _system_count}, state) do
    # For updates, we don't change active count, just log the event
    {:noreply, state}
  end

  @impl true
  def handle_info(:stats_summary, state) do
    log_stats_summary(state)
    schedule_stats_summary()
    {:noreply, state}
  end

  # Private helper functions

  defp schedule_stats_summary do
    Process.send_after(self(), :stats_summary, @stats_summary_interval)
  end

  defp build_stats_response(state) do
    total_kills = state.kills_sent.realtime + state.kills_sent.preload
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.started_at)

    %{
      kills_sent: %{
        realtime: state.kills_sent.realtime,
        preload: state.kills_sent.preload,
        total: total_kills
      },
      connections: %{
        active: state.connections.active,
        total_connected: state.connections.total_connected,
        total_disconnected: state.connections.total_disconnected
      },
      subscriptions: %{
        active: state.subscriptions.active,
        total_added: state.subscriptions.total_added,
        total_removed: state.subscriptions.total_removed,
        total_systems: state.subscriptions.total_systems
      },
      rates: calculate_current_rates(state),
      uptime_seconds: uptime_seconds,
      started_at: DateTime.to_iso8601(state.started_at),
      last_reset: DateTime.to_iso8601(state.last_reset),
      timestamp: Clock.now_iso8601()
    }
  end

  defp calculate_current_rates(state) do
    uptime_minutes = max(1, DateTime.diff(DateTime.utc_now(), state.started_at) / 60)
    reset_minutes = max(1, DateTime.diff(DateTime.utc_now(), state.last_reset) / 60)

    total_kills = state.kills_sent.realtime + state.kills_sent.preload

    %{
      kills_per_minute: total_kills / reset_minutes,
      connections_per_minute: state.connections.total_connected / uptime_minutes,
      average_systems_per_subscription:
        if state.subscriptions.active > 0 do
          state.subscriptions.total_systems / state.subscriptions.active
        else
          0.0
        end
    }
  end

  defp calculate_rate(stats) do
    {:ok, last_reset, _} = DateTime.from_iso8601(stats.last_reset)
    reset_minutes = max(1, DateTime.diff(DateTime.utc_now(), last_reset) / 60)
    stats.kills_sent.total / reset_minutes
  end

  defp log_stats_summary(state) do
    stats = build_stats_response(state)

    # Gather additional system-wide statistics
    {redisq_stats, cache_stats, store_stats} = gather_system_stats()

    # Log each component as a separate line item
    log_websocket_stats(stats)
    log_redisq_stats(redisq_stats)
    log_cache_stats(cache_stats)
    log_store_stats(store_stats)

    # Emit telemetry for the summary
    :telemetry.execute(
      [:wanderer_kills, :websocket, :summary],
      %{
        active_connections: stats.connections.active,
        total_kills_sent: stats.kills_sent.total,
        active_subscriptions: stats.subscriptions.active,
        kills_per_minute: stats.rates.kills_per_minute,
        total_systems: stats.subscriptions.total_systems
      },
      %{period: "5_minutes"}
    )
  end

  defp log_websocket_stats(stats) do
    LogFormatter.format_stats("WebSocket", %{
      connections_active: stats.connections.active,
      connections_total: stats.connections.total_connected,
      subscriptions: stats.subscriptions.active,
      systems: stats.subscriptions.total_systems,
      kills_sent: stats.kills_sent.total,
      kills_per_min: Float.round(stats.rates.kills_per_minute, 1)
    })
    |> Logger.info(
      websocket_active_connections: stats.connections.active,
      websocket_kills_sent_total: stats.kills_sent.total,
      websocket_kills_sent_realtime: stats.kills_sent.realtime,
      websocket_kills_sent_preload: stats.kills_sent.preload,
      websocket_active_subscriptions: stats.subscriptions.active,
      websocket_total_systems: stats.subscriptions.total_systems,
      websocket_kills_per_minute: Float.round(stats.rates.kills_per_minute, 2)
    )
  end

  defp log_redisq_stats(redisq_stats) when map_size(redisq_stats) > 0 do
    Logger.info(
      "[RedisQ Stats] Kills processed: #{Map.get(redisq_stats, :kills_processed, 0)} | " <>
        "Active systems: #{Map.get(redisq_stats, :active_systems, 0)} | " <>
        "Queue size: #{Map.get(redisq_stats, :queue_size, 0)}",
      redisq_kills_processed: Map.get(redisq_stats, :kills_processed, 0),
      redisq_active_systems: Map.get(redisq_stats, :active_systems, 0),
      redisq_queue_size: Map.get(redisq_stats, :queue_size, 0)
    )
  end

  defp log_redisq_stats(_), do: :ok

  defp log_cache_stats(cache_stats) when map_size(cache_stats) > 0 do
    # Ensure memory_mb is a float before rounding
    memory_mb_raw = Map.get(cache_stats, :memory_mb, 0.0)
    size_mb = Float.round(memory_mb_raw / 1, 1)

    # Extract all metrics
    size = Map.get(cache_stats, :size, 0)
    hit_rate = Map.get(cache_stats, :hit_rate, "N/A")
    miss_rate = Map.get(cache_stats, :miss_rate, 0.0)
    evictions = Map.get(cache_stats, :eviction_count, 0)
    expirations = Map.get(cache_stats, :expiration_count, 0)
    updates = Map.get(cache_stats, :update_count, 0)

    # Operation counts
    ops = Map.get(cache_stats, :operation_counts, %{})
    gets = Map.get(ops, :gets, 0)
    puts = Map.get(ops, :puts, 0)
    deletes = Map.get(ops, :deletes, 0)

    # Calculate memory efficiency (entries per MB)
    memory_efficiency = if size_mb > 0, do: Float.round(size / size_mb, 1), else: 0.0

    Logger.info(
      "[Cache Stats] Size: #{size} entries | " <>
        "Memory: #{size_mb} MB (#{memory_efficiency} entries/MB) | " <>
        "Hit/Miss: #{hit_rate}%/#{miss_rate}% | " <>
        "Evictions: #{evictions} | Expirations: #{expirations} | " <>
        "Ops (G/P/D): #{gets}/#{puts}/#{deletes}",
      cache_size: size,
      cache_memory_mb: size_mb,
      cache_memory_efficiency: memory_efficiency,
      cache_hit_rate: hit_rate,
      cache_miss_rate: miss_rate,
      cache_eviction_count: evictions,
      cache_expiration_count: expirations,
      cache_update_count: updates,
      cache_gets: gets,
      cache_puts: puts,
      cache_deletes: deletes
    )
  end

  defp log_cache_stats(_), do: :ok

  defp log_store_stats(store_stats) when map_size(store_stats) > 0 do
    # Ensure memory_mb is a float before rounding
    memory_mb_raw = Map.get(store_stats, :memory_mb, 0.0)
    memory_mb = Float.round(memory_mb_raw / 1, 1)

    Logger.info(
      "[Store Stats] Killmails: #{Map.get(store_stats, :total_killmails, 0)} | " <>
        "Systems: #{Map.get(store_stats, :unique_systems, 0)} | " <>
        "Memory: #{memory_mb} MB",
      store_total_killmails: Map.get(store_stats, :total_killmails, 0),
      store_unique_systems: Map.get(store_stats, :unique_systems, 0),
      store_memory_mb: memory_mb
    )
  end

  defp log_store_stats(_), do: :ok

  # Gather statistics from other system components
  defp gather_system_stats do
    redisq_stats = get_redisq_stats()
    cache_stats = get_cache_stats()
    store_stats = get_store_stats()

    {redisq_stats, cache_stats, store_stats}
  end

  defp get_redisq_stats do
    # Try to get stats from RedisQ GenServer if available
    try do
      case GenServer.call(WandererKills.RedisQ, :get_stats, 1000) do
        {:ok, stats} -> stats
        _ -> %{}
      end
    catch
      _, _ -> %{}
    end
  end

  defp get_cache_stats do
    # Get cache stats from Cachex
    try do
      case Cachex.size(:wanderer_cache) do
        {:ok, size} ->
          stats = fetch_cache_stats()
          build_cache_metrics(size, stats)

        _ ->
          empty_cache_stats()
      end
    catch
      _, _ ->
        empty_cache_stats()
    end
  end

  defp fetch_cache_stats do
    case Cachex.stats(:wanderer_cache) do
      {:ok, cache_stats} -> cache_stats
      _ -> %{}
    end
  end

  defp build_cache_metrics(size, stats) do
    # Extract statistics
    metrics = extract_cache_metrics(stats)

    # Calculate rates
    hit_rate = calculate_hit_rate(stats)
    miss_rate = calculate_miss_rate(metrics.hits, metrics.misses)

    # Estimate memory usage (rough calculation)
    # Rough estimate: 1KB per entry, convert KB to MB using binary units
    memory_mb = size / 1024

    %{
      size: size,
      memory_mb: memory_mb,
      hit_rate: hit_rate,
      miss_rate: miss_rate,
      eviction_count: metrics.evictions,
      expiration_count: metrics.expirations,
      update_count: metrics.updates,
      operation_counts: %{
        gets: metrics.gets,
        puts: metrics.puts,
        deletes: metrics.deletes
      }
    }
  end

  defp extract_cache_metrics(stats) do
    # The stats structure is flat, not nested under :value
    calls = Map.get(stats, :calls, %{})

    %{
      hits: Map.get(stats, :hits, 0),
      misses: Map.get(stats, :misses, 0),
      evictions: Map.get(stats, :evictions, 0),
      expirations: Map.get(stats, :expirations, 0),
      updates: Map.get(stats, :updates, 0),
      gets: Map.get(calls, :get, 0),
      puts: Map.get(calls, :put, 0),
      deletes: Map.get(calls, :del, 0)
    }
  end

  defp calculate_miss_rate(hits, misses) do
    total = hits + misses
    if total > 0, do: Float.round(misses / total * 100, 1), else: 0.0
  end

  defp empty_cache_stats do
    %{
      size: 0,
      memory_mb: 0.0,
      hit_rate: "N/A",
      miss_rate: 0.0,
      eviction_count: 0,
      expiration_count: 0,
      update_count: 0,
      operation_counts: %{gets: 0, puts: 0, deletes: 0}
    }
  end

  defp get_store_stats do
    # Get ETS store statistics
    try do
      killmails_count = :ets.info(:killmails, :size) || 0
      systems_count = :ets.info(:system_killmails, :size) || 0

      # Calculate average killmails per system
      avg_per_system =
        if systems_count > 0 do
          Float.round(killmails_count / systems_count, 1)
        else
          0.0
        end

      # Estimate memory usage for ETS tables (rough calculation)
      # Approximate 200 bytes per killmail entry
      memory_mb = killmails_count * 200 / (1024 * 1024)

      %{
        total_killmails: killmails_count,
        unique_systems: systems_count,
        avg_killmails_per_system: avg_per_system,
        memory_mb: memory_mb
      }
    catch
      _, _ -> %{}
    end
  end

  # Helper function to calculate hit rate from Cachex stats
  defp calculate_hit_rate(stats) when is_map(stats) and map_size(stats) > 0 do
    # Cachex stats has flat structure
    hits = Map.get(stats, :hits, 0)
    misses = Map.get(stats, :misses, 0)
    total_ops = hits + misses

    if total_ops > 0 do
      Float.round(hits / total_ops * 100, 1)
    else
      "N/A"
    end
  end

  defp calculate_hit_rate(_), do: "N/A"
end
