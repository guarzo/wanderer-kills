defmodule WandererKills.Observability.Metrics do
  @moduledoc """
  Unified metrics collection and management for WandererKills.
  
  This module consolidates all metric collection, aggregation, and reporting
  functionality that was previously scattered across the codebase. It provides
  a single interface for:
  
  - HTTP request metrics
  - Cache operation metrics
  - Killmail processing metrics
  - WebSocket connection metrics
  - System resource metrics
  - ESI API metrics
  - ZKillboard metrics
  
  All metrics are emitted as telemetry events for easy integration with
  monitoring tools like Prometheus, StatsD, or custom reporters.
  
  ## Usage
  
  ```elixir
  # Record a successful HTTP request
  Metrics.record_http_request(:zkb, :get, 200, 45.5)
  
  # Record cache operation
  Metrics.record_cache_operation(:wanderer_cache, :hit)
  
  # Record killmail processing
  Metrics.record_killmail_processed(:stored, 123456)
  
  # Get current metrics
  {:ok, metrics} = Metrics.get_all_metrics()
  ```
  """
  
  use GenServer
  require Logger
  
  alias WandererKills.Observability.{Telemetry, Statistics}
  alias WandererKills.Support.Clock
  
  # Metric types
  @type metric_name :: atom()
  @type metric_value :: number() | map()
  @type metric_metadata :: map()
  
  # Service names
  @type service :: :esi | :zkb | :http | :cache | :killmail | :websocket | :system
  
  # Operation results
  @type operation_result :: :success | :failure | :timeout | :error
  
  # Cache operations
  @type cache_operation :: :hit | :miss | :put | :eviction | :expired
  
  # Killmail processing results
  @type killmail_result :: :stored | :skipped | :failed | :enriched | :validated
  
  @type state :: %{
    start_time: DateTime.t(),
    metrics: map(),
    counters: map(),
    gauges: map(),
    histograms: map()
  }
  
  # ============================================================================
  # Client API
  # ============================================================================
  
  @doc """
  Starts the metrics GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Records an HTTP request metric.
  
  ## Parameters
  - `service` - The service making the request (:esi, :zkb, etc.)
  - `method` - HTTP method (:get, :post, etc.)
  - `status_code` - HTTP status code
  - `duration_ms` - Request duration in milliseconds
  - `metadata` - Additional metadata
  """
  @spec record_http_request(service(), atom(), integer(), number(), map()) :: :ok
  def record_http_request(service, method, status_code, duration_ms, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_http, service, method, status_code, duration_ms, metadata})
  end
  
  @doc """
  Records a cache operation metric.
  
  ## Parameters
  - `cache_name` - Name of the cache
  - `operation` - Type of operation (:hit, :miss, :put, :eviction)
  - `metadata` - Additional metadata
  """
  @spec record_cache_operation(atom(), cache_operation(), map()) :: :ok
  def record_cache_operation(cache_name, operation, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_cache, cache_name, operation, metadata})
  end
  
  @doc """
  Records a killmail processing metric.
  
  ## Parameters
  - `result` - Processing result (:stored, :skipped, :failed, etc.)
  - `killmail_id` - The killmail ID
  - `metadata` - Additional metadata
  """
  @spec record_killmail_processed(killmail_result(), integer(), map()) :: :ok
  def record_killmail_processed(result, killmail_id, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_killmail, result, killmail_id, metadata})
  end
  
  @doc """
  Records a WebSocket event metric.
  
  ## Parameters
  - `event` - Event type (:connection, :subscription, :kills_sent, etc.)
  - `value` - Numeric value (count, duration, etc.)
  - `metadata` - Additional metadata
  """
  @spec record_websocket_event(atom(), number(), map()) :: :ok
  def record_websocket_event(event, value, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_websocket, event, value, metadata})
  end
  
  @doc """
  Records a system resource metric.
  
  ## Parameters
  - `resource` - Resource type (:memory, :cpu, :processes, etc.)
  - `value` - Metric value
  - `metadata` - Additional metadata
  """
  @spec record_system_metric(atom(), number(), map()) :: :ok
  def record_system_metric(resource, value, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_system, resource, value, metadata})
  end
  
  @doc """
  Updates a gauge metric.
  
  ## Parameters
  - `name` - Gauge name
  - `value` - New value
  """
  @spec set_gauge(atom(), number()) :: :ok
  def set_gauge(name, value) when is_number(value) do
    GenServer.cast(__MODULE__, {:set_gauge, name, value})
  end
  
  @doc """
  Increments a counter metric.
  
  ## Parameters
  - `name` - Counter name
  - `amount` - Amount to increment (default: 1)
  """
  @spec increment_counter(atom(), number()) :: :ok
  def increment_counter(name, amount \\ 1) when is_number(amount) do
    GenServer.cast(__MODULE__, {:increment_counter, name, amount})
  end
  
  @doc """
  Records a value in a histogram.
  
  ## Parameters
  - `name` - Histogram name
  - `value` - Value to record
  """
  @spec record_histogram(atom(), number()) :: :ok
  def record_histogram(name, value) when is_number(value) do
    GenServer.cast(__MODULE__, {:record_histogram, name, value})
  end
  
  @doc """
  Gets all current metrics.
  
  ## Returns
  - `{:ok, metrics}` - All metrics as a map
  """
  @spec get_all_metrics() :: {:ok, map()}
  def get_all_metrics do
    GenServer.call(__MODULE__, :get_all_metrics)
  end
  
  @doc """
  Gets metrics for a specific service.
  
  ## Parameters
  - `service` - Service name
  
  ## Returns
  - `{:ok, metrics}` - Service-specific metrics
  """
  @spec get_service_metrics(service()) :: {:ok, map()}
  def get_service_metrics(service) do
    GenServer.call(__MODULE__, {:get_service_metrics, service})
  end
  
  @doc """
  Resets all metrics.
  """
  @spec reset_metrics() :: :ok
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end
  
  # ============================================================================
  # Convenience Functions for Common Metrics
  # ============================================================================
  
  @doc """
  Records a successful operation.
  """
  @spec record_success(service(), atom()) :: :ok
  def record_success(service, operation) do
    increment_counter(:"#{service}.#{operation}.success")
    increment_counter(:"#{service}.#{operation}.total")
  end
  
  @doc """
  Records a failed operation.
  """
  @spec record_failure(service(), atom(), atom()) :: :ok
  def record_failure(service, operation, reason) do
    increment_counter(:"#{service}.#{operation}.failure")
    increment_counter(:"#{service}.#{operation}.failure.#{reason}")
    increment_counter(:"#{service}.#{operation}.total")
  end
  
  @doc """
  Records operation duration.
  """
  @spec record_duration(service(), atom(), number()) :: :ok
  def record_duration(service, operation, duration_ms) do
    record_histogram(:"#{service}.#{operation}.duration_ms", duration_ms)
  end
  
  # ============================================================================
  # Parser Compatibility Functions
  # ============================================================================
  
  @doc """
  Increments the count of successfully stored killmails.
  """
  @spec increment_stored() :: :ok
  def increment_stored do
    increment_counter(:killmail_stored)
    Telemetry.parser_stored()
  end
  
  @doc """
  Increments the count of skipped killmails.
  """
  @spec increment_skipped() :: :ok
  def increment_skipped do
    increment_counter(:killmail_skipped)
    Telemetry.parser_skipped()
  end
  
  @doc """
  Increments the count of failed killmails.
  """
  @spec increment_failed() :: :ok
  def increment_failed do
    increment_counter(:killmail_failed)
    Telemetry.parser_failed()
  end
  
  # ============================================================================
  # GenServer Callbacks
  # ============================================================================
  
  @impl true
  def init(_opts) do
    Logger.info("[Metrics] Starting unified metrics collection")
    
    state = %{
      start_time: DateTime.utc_now(),
      metrics: %{},
      counters: %{},
      gauges: %{},
      histograms: %{}
    }
    
    # Schedule periodic metric emission
    schedule_metric_emission()
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record_http, service, method, status_code, duration_ms, metadata}, state) do
    # Emit telemetry event
    :telemetry.execute(
      [:wanderer_kills, :http, :request],
      %{duration_ms: duration_ms, status_code: status_code},
      Map.merge(metadata, %{service: service, method: method})
    )
    
    # Update counters
    status_class = div(status_code, 100)
    new_state = state
    |> increment_counter_internal(:"http.#{service}.requests")
    |> increment_counter_internal(:"http.#{service}.#{method}")
    |> increment_counter_internal(:"http.#{service}.status.#{status_class}xx")
    |> record_histogram_internal(:"http.#{service}.duration_ms", duration_ms)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_cache, cache_name, operation, metadata}, state) do
    # Emit telemetry event
    :telemetry.execute(
      [:wanderer_kills, :cache, operation],
      %{count: 1},
      Map.merge(metadata, %{cache: cache_name})
    )
    
    # Update counters
    new_state = state
    |> increment_counter_internal(:"cache.#{cache_name}.#{operation}")
    |> increment_counter_internal(:"cache.#{cache_name}.total")
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_killmail, result, killmail_id, metadata}, state) do
    # Emit telemetry event
    :telemetry.execute(
      [:wanderer_kills, :killmail, result],
      %{killmail_id: killmail_id},
      metadata
    )
    
    # Update counters
    new_state = state
    |> increment_counter_internal(:"killmail.#{result}")
    |> increment_counter_internal(:killmail_total)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_websocket, event, value, metadata}, state) do
    # Emit telemetry event
    :telemetry.execute(
      [:wanderer_kills, :websocket, event],
      %{value: value},
      metadata
    )
    
    # Update appropriate metric type
    new_state = case event do
      :connection -> increment_counter_internal(state, :websocket_connections)
      :disconnection -> increment_counter_internal(state, :websocket_disconnections)
      :kills_sent -> increment_counter_internal(state, :websocket_kills_sent, value)
      _ -> state
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_system, resource, value, metadata}, state) do
    # Emit telemetry event
    :telemetry.execute(
      [:wanderer_kills, :system, resource],
      %{value: value},
      metadata
    )
    
    # Update gauge
    new_state = set_gauge_internal(state, :"system.#{resource}", value)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:set_gauge, name, value}, state) do
    new_state = set_gauge_internal(state, name, value)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:increment_counter, name, amount}, state) do
    new_state = increment_counter_internal(state, name, amount)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:record_histogram, name, value}, state) do
    new_state = record_histogram_internal(state, name, value)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call(:get_all_metrics, _from, state) do
    metrics = build_all_metrics(state)
    {:reply, {:ok, metrics}, state}
  end
  
  @impl true
  def handle_call({:get_service_metrics, service}, _from, state) do
    metrics = build_service_metrics(state, service)
    {:reply, {:ok, metrics}, state}
  end
  
  @impl true
  def handle_call(:reset_metrics, _from, state) do
    new_state = %{state | 
      counters: %{},
      gauges: %{},
      histograms: %{},
      metrics: %{}
    }
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_info(:emit_metrics, state) do
    # Emit aggregated metrics periodically
    emit_aggregated_metrics(state)
    schedule_metric_emission()
    {:noreply, state}
  end
  
  # ============================================================================
  # Private Functions
  # ============================================================================
  
  defp schedule_metric_emission do
    # Emit metrics every 30 seconds
    Process.send_after(self(), :emit_metrics, 30_000)
  end
  
  defp increment_counter_internal(state, name, amount \\ 1) do
    counters = Map.update(state.counters, name, amount, &(&1 + amount))
    %{state | counters: counters}
  end
  
  defp set_gauge_internal(state, name, value) do
    gauges = Map.put(state.gauges, name, value)
    %{state | gauges: gauges}
  end
  
  defp record_histogram_internal(state, name, value) do
    histogram = Map.get(state.histograms, name, [])
    histograms = Map.put(state.histograms, name, [value | histogram])
    %{state | histograms: histograms}
  end
  
  defp build_all_metrics(state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)
    
    %{
      timestamp: Clock.now_iso8601(),
      uptime_seconds: uptime_seconds,
      counters: state.counters,
      gauges: state.gauges,
      histograms: calculate_histogram_stats(state.histograms),
      rates: calculate_rates(state.counters, uptime_seconds)
    }
  end
  
  defp build_service_metrics(state, service) do
    service_prefix = Atom.to_string(service)
    
    counters = state.counters
    |> Enum.filter(fn {key, _} -> String.starts_with?(Atom.to_string(key), service_prefix) end)
    |> Map.new()
    
    gauges = state.gauges
    |> Enum.filter(fn {key, _} -> String.starts_with?(Atom.to_string(key), service_prefix) end)
    |> Map.new()
    
    histograms = state.histograms
    |> Enum.filter(fn {key, _} -> String.starts_with?(Atom.to_string(key), service_prefix) end)
    |> calculate_histogram_stats()
    
    %{
      service: service,
      timestamp: Clock.now_iso8601(),
      counters: counters,
      gauges: gauges,
      histograms: histograms
    }
  end
  
  defp calculate_histogram_stats(histograms) do
    histograms
    |> Enum.map(fn {name, values} ->
      sorted = Enum.sort(values)
      count = length(values)
      
      stats = if count > 0 do
        %{
          count: count,
          min: List.first(sorted),
          max: List.last(sorted),
          mean: Enum.sum(values) / count,
          p50: percentile(sorted, 0.5),
          p95: percentile(sorted, 0.95),
          p99: percentile(sorted, 0.99)
        }
      else
        %{count: 0}
      end
      
      {name, stats}
    end)
    |> Map.new()
  end
  
  defp calculate_rates(counters, duration_seconds) do
    counters
    |> Enum.map(fn {name, count} ->
      rate = if duration_seconds > 0, do: count / duration_seconds, else: 0
      {:"#{name}_per_second", Float.round(rate, 2)}
    end)
    |> Map.new()
  end
  
  defp percentile(sorted_list, p) when is_list(sorted_list) and p >= 0 and p <= 1 do
    count = length(sorted_list)
    k = (count - 1) * p
    f = :math.floor(k)
    c = :math.ceil(k)
    
    if f == c do
      Enum.at(sorted_list, trunc(k))
    else
      d0 = Enum.at(sorted_list, trunc(f)) * (c - k)
      d1 = Enum.at(sorted_list, trunc(c)) * (k - f)
      d0 + d1
    end
  end
  
  defp emit_aggregated_metrics(state) do
    # Emit system-wide metrics
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.start_time)
    
    # HTTP metrics
    http_total = count_by_prefix(state.counters, "http.")
    http_success = count_by_prefix(state.counters, "http.", "status.2")
    http_errors = count_by_prefix(state.counters, "http.", "status.4") + 
                  count_by_prefix(state.counters, "http.", "status.5")
    
    :telemetry.execute(
      [:wanderer_kills, :metrics, :summary],
      %{
        http_requests_total: http_total,
        http_success_rate: Statistics.calculate_success_rate(http_success, http_total),
        http_error_rate: Statistics.calculate_percentage(http_errors, http_total),
        killmails_processed: Map.get(state.counters, :killmail_total, 0),
        killmails_stored: Map.get(state.counters, :killmail_stored, 0),
        killmails_skipped: Map.get(state.counters, :killmail_skipped, 0),
        killmails_failed: Map.get(state.counters, :killmail_failed, 0),
        uptime_seconds: uptime_seconds
      },
      %{timestamp: Clock.now_iso8601()}
    )
  end
  
  defp count_by_prefix(counters, prefix, contains \\ nil) do
    counters
    |> Enum.filter(fn {key, _} -> 
      key_str = Atom.to_string(key)
      starts_with = String.starts_with?(key_str, prefix)
      contains_match = is_nil(contains) or String.contains?(key_str, contains)
      starts_with and contains_match
    end)
    |> Enum.map(fn {_, value} -> value end)
    |> Enum.sum()
  end
end