defmodule WandererKills.App.EtsManager do
  @moduledoc """
  Manages ETS tables for the application.

  This GenServer ensures ETS tables are created at application start
  and are properly owned by a long-lived process.
  """

  use GenServer
  require Logger

  @websocket_stats_table :websocket_stats

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting ETS Manager")

    # Create the websocket stats table
    :ets.new(@websocket_stats_table, [:named_table, :public, :set])
    :ets.insert(@websocket_stats_table, {:kills_sent_realtime, 0})
    :ets.insert(@websocket_stats_table, {:kills_sent_preload, 0})
    :ets.insert(@websocket_stats_table, {:last_reset, DateTime.utc_now()})

    Logger.info("ETS tables initialized successfully")

    {:ok, %{tables: [@websocket_stats_table]}}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    # If we crash, the ETS tables will be lost, but the supervisor will restart us
    {:noreply, state}
  end

  @doc """
  Get the websocket stats table name.
  """
  def websocket_stats_table, do: @websocket_stats_table
end
