defmodule WandererKills.Core.Observability.ApiTracker do
  @moduledoc """
  Tracks API call statistics for external services (zkillboard and ESI).

  Monitors:
  - Request counts per minute using sliding window
  - Response times (min/max/avg)
  - Error rates by status code
  - Rate limit status

  Uses ETS for high-performance metric storage with automatic cleanup.
  """

  use GenServer
  require Logger

  @table_name :api_tracker_metrics
  @window_size_ms :timer.minutes(5)
  @cleanup_interval_ms :timer.minutes(1)

  # API services we track
  @services [:zkillboard, :esi]

  # Pre-compile match spec for cleanup efficiency
  # Note: we can't use the cutoff value in a module attribute,
  # so we'll create a function that returns the compiled spec

  @type service :: :zkillboard | :esi
  @type metric :: %{
          timestamp: integer(),
          service: service(),
          endpoint: String.t() | nil,
          duration_ms: integer(),
          status_code: integer() | nil,
          error: boolean()
        }

  # Client API

  @doc """
  Starts the API tracker GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records an API request.
  """
  @spec track_request(service(), keyword()) :: :ok
  def track_request(service, opts) when service in @services do
    metric = %{
      timestamp: System.monotonic_time(:millisecond),
      service: service,
      endpoint: Keyword.get(opts, :endpoint),
      duration_ms: Keyword.get(opts, :duration_ms, 0),
      status_code: Keyword.get(opts, :status_code),
      error: Keyword.get(opts, :error, false)
    }

    GenServer.cast(__MODULE__, {:track_request, metric})
  end

  @doc """
  Gets current statistics for all services.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Gets statistics for a specific service.
  """
  @spec get_service_stats(service()) :: map()
  def get_service_stats(service) when service in @services do
    GenServer.call(__MODULE__, {:get_service_stats, service})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for metrics
    :ets.new(@table_name, [:set, :public, :named_table, {:write_concurrency, true}])

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)

    # Schedule telemetry attachment after init completes
    Process.send_after(self(), :attach_telemetry, 100)

    state = %{
      start_time: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:track_request, metric}, state) do
    # Store metric in ETS with unique key
    key = {metric.service, metric.timestamp, :rand.uniform(1_000_000)}
    :ets.insert(@table_name, {key, metric})

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      zkillboard: calculate_service_stats(:zkillboard),
      esi: calculate_service_stats(:esi),
      tracking_duration_minutes: tracking_duration_minutes(state)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:get_service_stats, service}, _from, state) do
    stats = calculate_service_stats(service)
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:attach_telemetry, state) do
    attach_telemetry_handlers()
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove metrics older than window size
    cutoff = System.monotonic_time(:millisecond) - @window_size_ms

    # Use pre-compiled match spec for efficient deletion
    :ets.select_delete(@table_name, cleanup_match_spec(cutoff))

    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)

    {:noreply, state}
  end

  # Private functions

  defp attach_telemetry_handlers do
    # Attach to HTTP telemetry events using attach_many for better performance
    :telemetry.attach_many(
      "api-tracker-http-events",
      [
        [:wanderer_kills, :http, :request, :stop],
        [:wanderer_kills, :http, :request, :error]
      ],
      &__MODULE__.handle_http_telemetry/4,
      nil
    )
  end

  @doc false
  def handle_http_telemetry(_event_name, measurements, metadata, _config) do
    service = determine_service(metadata)

    if service do
      track_request(service,
        endpoint: extract_endpoint(metadata),
        duration_ms: div(measurements[:duration] || 0, 1_000_000),
        status_code: metadata[:status_code],
        error: metadata[:error] != nil
      )
    end
  end

  # Service detection based on URL patterns
  # Future enhancement: Make this configuration-driven by reading patterns from config
  defp determine_service(%{url: url}) when is_binary(url) do
    cond do
      String.contains?(url, "zkillboard.com") -> :zkillboard
      String.contains?(url, "esi.evetech.net") -> :esi
      true -> nil
    end
  end

  defp determine_service(_), do: nil

  defp extract_endpoint(%{url: url}) when is_binary(url) do
    case URI.parse(url) do
      %{path: path} when is_binary(path) ->
        normalize_endpoint_path(path)

      _ ->
        nil
    end
  end

  defp extract_endpoint(_), do: nil

  defp normalize_endpoint_path(path) do
    path
    |> String.split("/")
    |> Enum.map(&replace_id_segment/1)
    |> Enum.join("/")
  end

  defp replace_id_segment(segment) do
    if String.match?(segment, ~r/^\d+$/), do: "{id}", else: segment
  end

  defp calculate_service_stats(service) do
    now = System.monotonic_time(:millisecond)
    window_start = now - :timer.minutes(5)
    one_minute_ago = now - :timer.minutes(1)

    # Get all metrics for this service within window
    match_spec = [
      {
        {{:"$1", :"$2", :_}, :"$3"},
        [
          {:==, :"$1", service},
          {:>, :"$2", window_start}
        ],
        [:"$3"]
      }
    ]

    metrics = :ets.select(@table_name, match_spec)

    # Calculate statistics
    total_count = length(metrics)
    recent_metrics = Enum.filter(metrics, &(&1.timestamp > one_minute_ago))
    recent_count = length(recent_metrics)

    error_count = Enum.count(metrics, & &1.error)
    successful_metrics = Enum.filter(metrics, &(!&1.error && &1.duration_ms > 0))

    durations = Enum.map(successful_metrics, & &1.duration_ms)

    avg_duration =
      if length(durations) > 0 do
        Enum.sum(durations) / length(durations)
      else
        0.0
      end

    # Group by endpoint
    endpoint_stats =
      metrics
      |> Enum.group_by(& &1.endpoint)
      |> Enum.map(fn {endpoint, endpoint_metrics} ->
        {endpoint || "unknown",
         %{
           count: length(endpoint_metrics),
           errors: Enum.count(endpoint_metrics, & &1.error)
         }}
      end)
      |> Enum.into(%{})

    %{
      total_requests: total_count,
      requests_per_minute: recent_count,
      error_count: error_count,
      error_rate: if(total_count > 0, do: error_count / total_count * 100, else: 0.0),
      avg_duration_ms: Float.round(avg_duration, 1),
      min_duration_ms: Enum.min(durations, fn -> 0 end),
      max_duration_ms: Enum.max(durations, fn -> 0 end),
      endpoints: endpoint_stats
    }
  end

  defp tracking_duration_minutes(state) do
    now = System.monotonic_time(:millisecond)
    div(now - state.start_time, :timer.minutes(1))
  end

  @impl true
  def terminate(_reason, _state) do
    # Clean up ETS table on termination
    if :ets.info(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    :ok
  end

  # Pre-compiled match spec function for cleanup efficiency
  defp cleanup_match_spec(cutoff) do
    [
      {
        {{:"$1", :"$2", :_}, %{timestamp: :"$2"}},
        [{:<, :"$2", cutoff}],
        [true]
      }
    ]
  end
end
