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

    # Create the websocket stats table with concurrency optimizations
    # Handle the case where table might already exist during hot-code reloads
    case :ets.info(@websocket_stats_table) do
      :undefined ->
        :ets.new(@websocket_stats_table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

        :ets.insert(@websocket_stats_table, {:kills_sent_realtime, 0})
        :ets.insert(@websocket_stats_table, {:kills_sent_preload, 0})
        :ets.insert(@websocket_stats_table, {:last_reset, DateTime.utc_now()})

      _ ->
        Logger.debug("ETS table #{@websocket_stats_table} already exists, skipping creation")
    end

    Logger.info("ETS tables initialized successfully")

    {:ok, %{tables: [@websocket_stats_table]}}
  end

  @doc """
  Get the websocket stats table name.
  """
  def websocket_stats_table, do: @websocket_stats_table
end
