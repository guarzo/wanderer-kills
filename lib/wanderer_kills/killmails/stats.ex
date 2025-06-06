defmodule WandererKills.Killmails.Stats do
  @moduledoc """
  Statistics tracking for killmail parsing operations.

  This module provides a focused API for tracking parser performance metrics
  and statistics. It follows the consistent "Killmail" naming convention.

  ## Features

  - Parse operation counters
  - Success/failure tracking
  - Performance metrics
  - Time-based statistics

  ## Usage

  ```elixir
  # Increment successful parses
  KillmailStats.increment_stored()

  # Increment skipped killmails
  KillmailStats.increment_skipped()

  # Get current statistics
  stats = KillmailStats.get_stats()
  ```
  """

  use GenServer
  require Logger

  @default_name __MODULE__

  @type stat_key :: :stored | :skipped | :failed | :total_processed
  @type stats :: %{
          stored: non_neg_integer(),
          skipped: non_neg_integer(),
          failed: non_neg_integer(),
          total_processed: non_neg_integer(),
          last_reset: DateTime.t()
        }

  # Client API

  @doc """
  Starts the killmail statistics tracking server.

  ## Options
  - `:name` - Process name (defaults to module name)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc """
  Increments the count of successfully stored killmails.
  """
  @spec increment_stored() :: :ok
  def increment_stored do
    GenServer.cast(@default_name, {:increment, :stored})
  end

  @doc """
  Increments the count of skipped killmails (too old).
  """
  @spec increment_skipped() :: :ok
  def increment_skipped do
    GenServer.cast(@default_name, {:increment, :skipped})
  end

  @doc """
  Increments the count of failed killmail parsing attempts.
  """
  @spec increment_failed() :: :ok
  def increment_failed do
    GenServer.cast(@default_name, {:increment, :failed})
  end

  @doc """
  Gets the current parsing statistics.

  ## Returns
  Map containing current counters and timestamps
  """
  @spec get_stats() :: stats()
  def get_stats do
    GenServer.call(@default_name, :get_stats)
  end

  @doc """
  Resets all statistics counters to zero.
  """
  @spec reset_stats() :: :ok
  def reset_stats do
    GenServer.call(@default_name, :reset_stats)
  end

  @doc """
  Gets statistics for a specific metric.

  ## Parameters
  - `key` - The statistic to retrieve

  ## Returns
  Current count for the specified metric
  """
  @spec get_stat(stat_key()) :: non_neg_integer()
  def get_stat(key) when key in [:stored, :skipped, :failed, :total_processed] do
    GenServer.call(@default_name, {:get_stat, key})
  end

  # Server callbacks

  @impl true
  def init(:ok) do
    state = %{
      stored: 0,
      skipped: 0,
      failed: 0,
      total_processed: 0,
      last_reset: DateTime.utc_now()
    }

    Logger.debug("KillmailStats server started", state: state)
    {:ok, state}
  end

  @impl true
  def handle_cast({:increment, key}, state) when key in [:stored, :skipped, :failed] do
    new_state =
      state
      |> Map.update!(key, &(&1 + 1))
      |> Map.update!(:total_processed, &(&1 + 1))

    Logger.debug("Incremented killmail stat", stat: key, new_value: new_state[key])
    {:noreply, new_state}
  end

  def handle_cast(unknown_msg, state) do
    Logger.warning("Unknown cast message in KillmailStats", message: unknown_msg)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:get_stat, key}, _from, state) do
    value = Map.get(state, key, 0)
    {:reply, value, state}
  end

  def handle_call(:reset_stats, _from, _state) do
    new_state = %{
      stored: 0,
      skipped: 0,
      failed: 0,
      total_processed: 0,
      last_reset: DateTime.utc_now()
    }

    Logger.info("KillmailStats counters reset", timestamp: new_state.last_reset)
    {:reply, :ok, new_state}
  end

  def handle_call(unknown_msg, from, state) do
    Logger.warning("Unknown call message in KillmailStats", message: unknown_msg, from: from)
    {:reply, {:error, :unknown_call}, state}
  end

  @impl true
  def handle_info(unknown_msg, state) do
    Logger.warning("Unknown info message in KillmailStats", message: unknown_msg)
    {:noreply, state}
  end
end
