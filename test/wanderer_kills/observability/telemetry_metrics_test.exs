defmodule WandererKills.Core.Observability.TelemetryMetricsTest do
  use ExUnit.Case, async: false

  alias WandererKills.Core.Observability.TelemetryMetrics

  setup do
    # Ensure clean state
    TelemetryMetrics.reset_metrics()
    :ok
  end

  describe "task event tracking" do
    test "tracks task start events" do
      # Emit a task start event
      :telemetry.execute(
        [:wanderer_kills, :task, :start],
        %{system_time: System.system_time()},
        %{task_name: "test_task"}
      )

      metrics = TelemetryMetrics.get_metrics()
      assert metrics[:tasks_started] == 1
    end

    test "tracks task completion events" do
      # Emit a task stop event
      :telemetry.execute(
        [:wanderer_kills, :task, :stop],
        %{duration: 1000},
        %{task_name: "test_task"}
      )

      metrics = TelemetryMetrics.get_metrics()
      assert metrics[:tasks_completed] == 1
    end

    test "tracks task error events" do
      # Emit a task error event
      :telemetry.execute(
        [:wanderer_kills, :task, :error],
        %{duration: 1000},
        %{task_name: "test_task", error: "Test error"}
      )

      metrics = TelemetryMetrics.get_metrics()
      assert metrics[:tasks_failed] == 1
    end
  end

  describe "preload task tracking" do
    test "tracks preload task events" do
      # Start a preload task
      :telemetry.execute(
        [:wanderer_kills, :task, :start],
        %{system_time: System.system_time()},
        %{task_name: "subscription_preload"}
      )

      # Complete it
      :telemetry.execute(
        [:wanderer_kills, :task, :stop],
        %{duration: 1000},
        %{task_name: "subscription_preload"}
      )

      metrics = TelemetryMetrics.get_metrics()
      assert metrics[:preload_tasks_started] == 1
      assert metrics[:preload_tasks_completed] == 1
      assert metrics[:preload_tasks_failed] == 0
    end

    test "tracks failed preload tasks" do
      # Start and fail a preload task
      :telemetry.execute(
        [:wanderer_kills, :task, :start],
        %{system_time: System.system_time()},
        %{task_name: "subscription_preload"}
      )

      :telemetry.execute(
        [:wanderer_kills, :task, :error],
        %{duration: 1000},
        %{task_name: "subscription_preload", error: "Test error"}
      )

      metrics = TelemetryMetrics.get_metrics()
      assert metrics[:preload_tasks_started] == 1
      assert metrics[:preload_tasks_failed] == 1
    end
  end

  describe "webhook task tracking" do
    test "tracks webhook notification tasks" do
      # Track webhook notification
      :telemetry.execute(
        [:wanderer_kills, :task, :start],
        %{system_time: System.system_time()},
        %{task_name: "webhook_notification"}
      )

      :telemetry.execute(
        [:wanderer_kills, :task, :stop],
        %{duration: 1000},
        %{task_name: "webhook_notification"}
      )

      metrics = TelemetryMetrics.get_metrics()
      assert metrics[:webhook_tasks_started] == 1
      assert metrics[:webhook_tasks_completed] == 1
      assert metrics[:webhooks_sent] == 1
    end

    test "tracks failed webhook tasks" do
      # Track failed webhook
      :telemetry.execute(
        [:wanderer_kills, :task, :start],
        %{system_time: System.system_time()},
        %{task_name: "send_webhook_notifications"}
      )

      :telemetry.execute(
        [:wanderer_kills, :task, :error],
        %{duration: 1000},
        %{task_name: "send_webhook_notifications", error: "Test error"}
      )

      metrics = TelemetryMetrics.get_metrics()
      assert metrics[:webhook_tasks_failed] == 1
      assert metrics[:webhooks_failed] == 1
    end
  end

  describe "metric retrieval" do
    test "get_metric returns default value for missing keys" do
      assert TelemetryMetrics.get_metric(:nonexistent) == 0
      assert TelemetryMetrics.get_metric(:nonexistent, 42) == 42
    end

    test "get_metrics returns all metrics" do
      # Emit some events
      :telemetry.execute(
        [:wanderer_kills, :task, :start],
        %{system_time: System.system_time()},
        %{task_name: "test"}
      )

      metrics = TelemetryMetrics.get_metrics()
      assert is_map(metrics)
      assert Map.has_key?(metrics, :tasks_started)
      assert metrics[:tasks_started] == 1
    end
  end

  describe "reset functionality" do
    test "reset_metrics clears all counters" do
      # Add some data
      :telemetry.execute(
        [:wanderer_kills, :task, :start],
        %{system_time: System.system_time()},
        %{task_name: "test"}
      )

      metrics = TelemetryMetrics.get_metrics()
      assert metrics[:tasks_started] == 1

      # Reset
      TelemetryMetrics.reset_metrics()

      # Check all counters are back to 0
      metrics = TelemetryMetrics.get_metrics()
      assert metrics[:tasks_started] == 0
      assert metrics[:tasks_completed] == 0
      assert metrics[:tasks_failed] == 0
    end
  end
end
