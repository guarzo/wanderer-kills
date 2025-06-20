defmodule WandererKills.Core.Storage.CleanupWorker do
  @moduledoc """
  Periodic cleanup worker for KillmailStore ETS tables.

  This GenServer runs periodic cleanup of old data based on configured TTLs:
  - killmails: 7 days
  - system_killmails: 7 days (cleaned with killmails)
  - system_kill_counts: Cleaned when system has no killmails
  - system_fetch_timestamps: 1 day
  - killmail_events: 7 days
  - client_offsets: 3 days

  The cleanup interval can be configured via:
  ```
  config :wanderer_kills, :storage,
    gc_interval_ms: 3_600_000  # 1 hour default
  ```
  """

  use GenServer
  require Logger

  alias WandererKills.Core.Storage.KillmailStore

  @default_interval_ms :timer.hours(1)

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the cleanup worker.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate cleanup.
  """
  def cleanup_now do
    GenServer.call(__MODULE__, :cleanup_now, :timer.seconds(30))
  end

  @doc """
  Gets the current cleanup statistics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    Logger.info("[CleanupWorker] Starting storage cleanup worker")

    # Get configured interval or use default
    interval = get_cleanup_interval()

    # Schedule first cleanup
    schedule_cleanup(interval)

    state = %{
      interval: interval,
      last_cleanup: nil,
      last_stats: nil,
      total_cleanups: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:cleanup_now, _from, state) do
    Logger.info("[CleanupWorker] Manual cleanup triggered")

    case perform_cleanup() do
      {:ok, stats} ->
        new_state = %{
          state
          | last_cleanup: DateTime.utc_now(),
            last_stats: stats,
            total_cleanups: state.total_cleanups + 1
        }

        {:reply, {:ok, stats}, new_state}

      {:error, reason} = error ->
        Logger.error("[CleanupWorker] Cleanup failed", error: reason)
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      last_cleanup: state.last_cleanup,
      last_stats: state.last_stats,
      total_cleanups: state.total_cleanups,
      next_cleanup_in: calculate_next_cleanup_time(state.interval),
      interval_ms: state.interval
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:perform_cleanup, state) do
    Logger.debug("[CleanupWorker] Starting scheduled cleanup")

    # Perform cleanup
    stats =
      case perform_cleanup() do
        {:ok, cleanup_stats} ->
          Logger.debug("[CleanupWorker] Cleanup completed", cleanup_stats)
          cleanup_stats

        {:error, reason} ->
          Logger.error("[CleanupWorker] Cleanup failed", error: reason)
          nil
      end

    # Schedule next cleanup
    schedule_cleanup(state.interval)

    # Update state
    new_state = %{
      state
      | last_cleanup: DateTime.utc_now(),
        last_stats: stats,
        total_cleanups: state.total_cleanups + 1
    }

    {:noreply, new_state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_cleanup_interval do
    Application.get_env(:wanderer_kills, :storage, [])
    |> Keyword.get(:gc_interval_ms, @default_interval_ms)
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :perform_cleanup, interval)
  end

  defp perform_cleanup do
    try do
      KillmailStore.cleanup_old_data()
    rescue
      e ->
        {:error, Exception.format(:error, e, __STACKTRACE__)}
    end
  end

  defp calculate_next_cleanup_time(interval) do
    # Returns milliseconds until next cleanup
    case Process.info(self(), :message_queue_len) do
      {_, 0} ->
        interval

      _ ->
        # If there's a pending message, calculate actual time remaining
        # This is approximate since we can't inspect timer references
        interval
    end
  end
end
