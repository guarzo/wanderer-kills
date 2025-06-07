defmodule WandererKills.Core.ETSManager do
  @moduledoc """
  GenServer that manages ETS table creation and lifecycle.

  This module creates ETS tables during initialization and ensures they
  remain accessible throughout the application lifecycle. It follows
  OTP best practices by separating table management from business logic.
  """

  use GenServer
  require Logger

  @type table_spec :: {atom(), [atom()], String.t()}

  @doc """
  Starts the ETS manager with the given table specifications.
  """
  @spec start_link([table_spec()]) :: GenServer.on_start()
  def start_link(table_specs) when is_list(table_specs) do
    GenServer.start_link(__MODULE__, table_specs, name: __MODULE__)
  end

  @doc """
  Gets information about all managed tables.
  """
  @spec get_table_info() :: {:ok, [map()]} | {:error, term()}
  def get_table_info do
    GenServer.call(__MODULE__, :get_table_info)
  end

  @doc """
  Checks if a specific table exists and is accessible.
  """
  @spec table_exists?(atom()) :: boolean()
  def table_exists?(table_name) when is_atom(table_name) do
    case :ets.whereis(table_name) do
      :undefined -> false
      _ -> true
    end
  end

  @doc """
  Gets the size of a specific table.
  """
  @spec table_size(atom()) :: {:ok, non_neg_integer()} | {:error, term()}
  def table_size(table_name) when is_atom(table_name) do
    try do
      size = :ets.info(table_name, :size)
      {:ok, size}
    rescue
      ArgumentError -> {:error, :table_not_found}
    end
  end

  # GenServer Callbacks

  @impl GenServer
  def init(table_specs) do
    Logger.info("Creating ETS tables", table_count: length(table_specs))

    created_tables =
      Enum.map(table_specs, fn {name, options, description} ->
        case create_table_if_not_exists(name, options) do
          :ok ->
            Logger.debug("Created ETS table", name: name, description: description)
            {name, options, description, :created}

          {:error, reason} ->
            Logger.error("Failed to create ETS table",
              name: name,
              description: description,
              error: reason
            )

            {name, options, description, {:error, reason}}
        end
      end)

    # Initialize sequence counter if counters table exists
    initialize_counters()

    state = %{
      tables: created_tables,
      created_at: DateTime.utc_now()
    }

    Logger.info("ETS manager initialized",
      total_tables: length(table_specs),
      successful_tables: count_successful_tables(created_tables)
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_table_info, _from, state) do
    table_info =
      Enum.map(state.tables, fn {name, options, description, status} ->
        size =
          case table_size(name) do
            {:ok, size} -> size
            {:error, _} -> :unknown
          end

        %{
          name: name,
          options: options,
          description: description,
          status: status,
          size: size,
          exists: table_exists?(name)
        }
      end)

    {:reply, {:ok, table_info}, state}
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    # Periodic health check (if needed in the future)
    {:noreply, state}
  end

  # Private Functions

  @spec create_table_if_not_exists(atom(), [atom()]) :: :ok | {:error, term()}
  defp create_table_if_not_exists(table_name, options) do
    case :ets.whereis(table_name) do
      :undefined ->
        try do
          case :ets.new(table_name, options) do
            ^table_name -> :ok
            error -> {:error, {:creation_failed, error}}
          end
        rescue
          error -> {:error, {:exception, error}}
        end

      _ ->
        # Table already exists
        :ok
    end
  end

  @spec initialize_counters() :: :ok
  defp initialize_counters do
    case table_exists?(:counters) do
      true ->
        case :ets.lookup(:counters, :killmail_seq) do
          [] ->
            :ets.insert(:counters, {:killmail_seq, 0})
            Logger.debug("Initialized killmail sequence counter")

          _ ->
            Logger.debug("Killmail sequence counter already exists")
        end

      false ->
        Logger.warning("Counters table not available for initialization")
    end

    :ok
  end

  @spec count_successful_tables([tuple()]) :: non_neg_integer()
  defp count_successful_tables(tables) do
    Enum.count(tables, fn {_name, _options, _description, status} ->
      status == :created
    end)
  end
end
