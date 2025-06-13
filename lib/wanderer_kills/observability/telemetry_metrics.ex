defmodule WandererKills.Observability.TelemetryMetrics do
  @moduledoc """
  Aggregates telemetry events into metrics for status reporting.

  This GenServer subscribes to telemetry events and maintains counters
  that can be queried by the unified status reporter.
  """

  use GenServer
  require Logger

  @table :telemetry_metrics

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current metric values.
  """
  def get_metrics do
    case :ets.info(@table) do
      :undefined ->
        %{}

      _ ->
        :ets.tab2list(@table)
        |> Enum.into(%{})
    end
  end

  @doc """
  Get a specific metric value.
  """
  def get_metric(key, default \\ 0) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  @doc """
  Reset all metrics to zero.
  """
  def reset_metrics do
    GenServer.call(__MODULE__, :reset_metrics)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for metrics
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

    # Initialize counters
    init_counters()

    # Attach telemetry handlers
    attach_handlers()

    Logger.info("[TelemetryMetrics] Started telemetry metrics aggregator")

    {:ok, %{}}
  end

  @impl true
  def handle_call(:reset_metrics, _from, state) do
    init_counters()
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    detach_handlers()
    :ok
  end

  # Private functions

  defp init_counters do
    # Task metrics
    :ets.insert(@table, {:tasks_started, 0})
    :ets.insert(@table, {:tasks_completed, 0})
    :ets.insert(@table, {:tasks_failed, 0})

    # Preload-specific task metrics
    :ets.insert(@table, {:preload_tasks_started, 0})
    :ets.insert(@table, {:preload_tasks_completed, 0})
    :ets.insert(@table, {:preload_tasks_failed, 0})

    # Webhook metrics
    :ets.insert(@table, {:webhook_tasks_started, 0})
    :ets.insert(@table, {:webhook_tasks_completed, 0})
    :ets.insert(@table, {:webhook_tasks_failed, 0})
    :ets.insert(@table, {:webhooks_sent, 0})
    :ets.insert(@table, {:webhooks_failed, 0})

    # Preload delivery metrics
    :ets.insert(@table, {:kills_delivered, 0})
  end

  defp attach_handlers do
    :telemetry.attach_many(
      "telemetry-metrics-task-handler",
      [
        [:wanderer_kills, :task, :start],
        [:wanderer_kills, :task, :stop],
        [:wanderer_kills, :task, :error]
      ],
      &handle_task_event/4,
      nil
    )

    :telemetry.attach(
      "telemetry-metrics-preload-handler",
      [:wanderer_kills, :preload, :kills_delivered],
      &handle_preload_event/4,
      nil
    )
  end

  defp detach_handlers do
    :telemetry.detach("telemetry-metrics-task-handler")
    :telemetry.detach("telemetry-metrics-preload-handler")
  end

  defp handle_task_event([:wanderer_kills, :task, :start], _measurements, metadata, _config) do
    increment_counter(:tasks_started)

    # Track specific task types
    case metadata[:task_name] do
      "subscription_preload" -> increment_counter(:preload_tasks_started)
      "websocket_preload" -> increment_counter(:preload_tasks_started)
      "webhook_notification" -> increment_counter(:webhook_tasks_started)
      "send_webhook_notifications" -> increment_counter(:webhook_tasks_started)
      _ -> :ok
    end
  end

  defp handle_task_event([:wanderer_kills, :task, :stop], _measurements, metadata, _config) do
    increment_counter(:tasks_completed)

    task_name = metadata[:task_name]
    Logger.info("[TelemetryMetrics] Task completed: #{inspect(task_name)}")

    # Track specific task types
    case task_name do
      "subscription_preload" ->
        increment_counter(:preload_tasks_completed)

      "websocket_preload" ->
        increment_counter(:preload_tasks_completed)

      "webhook_notification" ->
        increment_counter(:webhook_tasks_completed)
        increment_counter(:webhooks_sent)
        Logger.info("[TelemetryMetrics] Incremented webhook counters for: #{task_name}")

      "send_webhook_notifications" ->
        increment_counter(:webhook_tasks_completed)
        increment_counter(:webhooks_sent)
        Logger.info("[TelemetryMetrics] Incremented webhook counters for: #{task_name}")

      _ ->
        Logger.info("[TelemetryMetrics] Unknown task type: #{inspect(task_name)}")
    end
  end

  defp handle_task_event([:wanderer_kills, :task, :error], _measurements, metadata, _config) do
    increment_counter(:tasks_failed)

    # Track specific task types
    case metadata[:task_name] do
      "subscription_preload" ->
        increment_counter(:preload_tasks_failed)

      "websocket_preload" ->
        increment_counter(:preload_tasks_failed)

      "webhook_notification" ->
        increment_counter(:webhook_tasks_failed)
        increment_counter(:webhooks_failed)

      "send_webhook_notifications" ->
        increment_counter(:webhook_tasks_failed)
        increment_counter(:webhooks_failed)

      _ ->
        :ok
    end
  end

  defp handle_preload_event(
         [:wanderer_kills, :preload, :kills_delivered],
         measurements,
         _metadata,
         _config
       ) do
    count = Map.get(measurements, :count, 0)
    :ets.update_counter(@table, :kills_delivered, count, {:kills_delivered, 0})
  end

  defp increment_counter(key) do
    :ets.update_counter(@table, key, 1, {key, 0})
  end
end
