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
    # Store stats in ETS for unified status reporter
    stats = build_stats_response(state)
    :ets.insert(:wanderer_kills_stats, {:websocket_stats, stats})

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
end
