defmodule WandererKills.Core.ETSSupervisor do
  @moduledoc """
  Supervisor for ETS table management.

  This module manages the lifecycle of ETS tables separately from GenServer
  processes, following OTP best practices. ETS tables are created during
  supervisor initialization rather than in GenServer init callbacks.
  """

  use Supervisor
  require Logger

  @doc """
  Starts the ETS supervisor with the given options.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    Logger.info("Starting ETS supervisor and creating tables")

    children = [
      {WandererKills.Core.ETSManager, table_specs()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the specifications for all ETS tables used by the application.
  """
  @spec table_specs() :: [table_spec()]
  def table_specs do
    [
      # Killmail Store tables
      {:killmail_events, [:ordered_set, :public, :named_table], "Killmail events for streaming"},
      {:client_offsets, [:set, :public, :named_table], "Client offset tracking"},
      {:counters, [:set, :public, :named_table], "Sequence counters"},
      {:killmails, [:named_table, :set, :public], "Individual killmail storage"},
      {:system_killmails, [:named_table, :set, :public], "System to killmail mapping"},
      {:system_kill_counts, [:named_table, :set, :public], "Kill counts per system"},
      {:system_fetch_timestamps, [:named_table, :set, :public], "Fetch timestamps per system"}
    ]
  end

  @type table_spec :: {atom(), [atom()], String.t()}
end
