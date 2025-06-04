defmodule WandererKills.Parser.Stats do
  @moduledoc """
  Tracks statistics for killmail processing.
  """

  use GenServer
  require Logger
  alias WandererKills.Config
  alias WandererKills.Infrastructure.Telemetry

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def increment_stored do
    Telemetry.parser_stored()
    GenServer.cast(__MODULE__, :increment_stored)
  end

  def increment_skipped do
    Telemetry.parser_skipped()
    GenServer.cast(__MODULE__, :increment_skipped)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    schedule_summary()
    {:ok, %{stored: 0, skipped: 0}}
  end

  @impl true
  def handle_cast(:increment_stored, state) do
    {:noreply, %{state | stored: state.stored + 1}}
  end

  def handle_cast(:increment_skipped, state) do
    {:noreply, %{state | skipped: state.skipped + 1}}
  end

  @impl true
  def handle_info(:log_summary, state) do
    Telemetry.parser_summary(state.stored, state.skipped)

    Logger.info(
      "[Parser] Killmail processing summary - Stored: #{state.stored}, Skipped: #{state.skipped}"
    )

    schedule_summary()
    {:noreply, %{stored: 0, skipped: 0}}
  end

  defp schedule_summary do
    interval = Config.parser().summary_interval_ms
    Process.send_after(self(), :log_summary, interval)
  end
end
