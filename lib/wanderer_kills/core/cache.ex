defmodule WandererKills.Core.Cache do
  @moduledoc """
  Centralized caching module for WandererKills.

  This module provides a unified interface for all caching operations across the
  WandererKills application. It manages multiple ETS tables for different data types
  and provides advanced features like TTL expiration, system tracking, and kill counting.

  ## ETS Tables

  This module manages several ETS tables:

  - `:wanderer_kills_cache` - Main cache for general key-value storage
  - `:ship_types` - Ship type information cache
  - `:characters` - Character information cache
  - `:corporations` - Corporation information cache
  - `:alliances` - Alliance information cache
  - `:system_killmails` - System ID to killmail IDs mapping
  - `:active_systems` - Currently active systems with timestamps
  - `:system_fetch_timestamps` - Last fetch time per system
  - `:system_kill_counts` - Cached kill counts per system

  ## Usage Examples

      # Basic caching operations
      {:ok, :set} = WandererKills.Core.Cache.put(:ship_types, 12345, %{name: "Rifter"})
      {:ok, data} = WandererKills.Core.Cache.get(:ship_types, 12345)

      # System operations
      {:ok, :added} = WandererKills.Core.Cache.add_system_killmail(30000142, [12345, 67890])
      {:ok, killmails} = WandererKills.Core.Cache.get_killmails_for_system(30000142)

      # Active system tracking
      {:ok, :added} = WandererKills.Core.Cache.add_active_system(30000142)
      {:ok, systems} = WandererKills.Core.Cache.get_active_systems()

      # Kill count management
      {:ok, 5} = WandererKills.Core.Cache.increment_system_kill_count(30000142)
  """

  use GenServer
  require Logger

  alias WandererKills.Core.Config
  alias WandererKills.Core.Error
  alias WandererKills.Core.Clock

  # Table definitions
  @cache_table :wanderer_kills_cache
  @ship_types_table :ship_types
  @characters_table :characters
  @corporations_table :corporations
  @alliances_table :alliances
  @system_killmails_table :system_killmails
  @active_systems_table :active_systems
  @system_fetch_timestamps_table :system_fetch_timestamps
  @system_kill_counts_table :system_kill_counts

  @all_tables [
    @cache_table,
    @ship_types_table,
    @characters_table,
    @corporations_table,
    @alliances_table,
    @system_killmails_table,
    @active_systems_table,
    @system_fetch_timestamps_table,
    @system_kill_counts_table
  ]

  ## GenServer API

  @type table_name :: atom()
  @type cache_key :: term()
  @type cache_value :: term()
  @type ttl_seconds :: pos_integer()
  @type table_spec :: {table_name(), [atom()], String.t()}

  @type cache_entry :: {cache_key(), cache_value(), integer() | :never}
  @type cache_stats :: %{
          name: table_name(),
          size: non_neg_integer(),
          memory: non_neg_integer(),
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          created_at: DateTime.t()
        }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the cache manager with default or custom table specifications.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    table_names = Keyword.get(opts, :tables, @all_tables)
    table_specs = create_table_specs(table_names)
    GenServer.start_link(__MODULE__, table_specs, name: __MODULE__)
  end

  @doc """
  Returns a child specification for starting this module under a supervisor.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Gets a value from the cache.
  """
  @spec get(table_name(), cache_key()) :: {:ok, cache_value()} | {:error, Error.t()}
  def get(table, key) do
    try do
      case :ets.lookup(table, key) do
        [{^key, value, :never}] ->
          increment_stat(table, :hits)
          {:ok, value}

        [{^key, value, expires_at}] ->
          if Clock.now_milliseconds() < expires_at do
            increment_stat(table, :hits)
            {:ok, value}
          else
            # Entry expired, remove it
            :ets.delete(table, key)
            increment_stat(table, :misses)
            {:error, Error.cache_error(:expired, "Cache entry expired")}
          end

        [] ->
          increment_stat(table, :misses)
          {:error, Error.cache_error(:not_found, "Cache key not found")}
      end
    rescue
      ArgumentError ->
        {:error,
         Error.cache_error(:table_not_found, "Cache table does not exist", %{table: table})}
    end
  end

  @doc """
  Puts a value in the cache without TTL.
  """
  @spec put(table_name(), cache_key(), cache_value()) :: :ok | {:error, Error.t()}
  def put(table, key, value) do
    try do
      :ets.insert(table, {key, value, :never})
      :ok
    rescue
      ArgumentError ->
        {:error,
         Error.cache_error(:table_not_found, "Cache table does not exist", %{table: table})}
    end
  end

  @doc """
  Puts a value in the cache with TTL in seconds.
  """
  @spec put_with_ttl(table_name(), cache_key(), cache_value(), ttl_seconds()) ::
          :ok | {:error, Error.t()}
  def put_with_ttl(table, key, value, ttl_seconds) do
    expires_at = Clock.now_milliseconds() + ttl_seconds * 1000

    try do
      :ets.insert(table, {key, value, expires_at})
      :ok
    rescue
      ArgumentError ->
        {:error,
         Error.cache_error(:table_not_found, "Cache table does not exist", %{table: table})}
    end
  end

  @doc """
  Deletes a key from the cache.
  """
  @spec delete(table_name(), cache_key()) :: :ok | {:error, Error.t()}
  def delete(table, key) do
    try do
      :ets.delete(table, key)
      :ok
    rescue
      ArgumentError ->
        {:error,
         Error.cache_error(:table_not_found, "Cache table does not exist", %{table: table})}
    end
  end

  @doc """
  Clears all entries from a cache table.
  """
  @spec clear(table_name()) :: :ok | {:error, Error.t()}
  def clear(table) do
    try do
      :ets.delete_all_objects(table)
      :ok
    rescue
      ArgumentError ->
        {:error,
         Error.cache_error(:table_not_found, "Cache table does not exist", %{table: table})}
    end
  end

  @doc """
  Gets cache statistics for a table.
  """
  @spec stats(table_name()) :: {:ok, cache_stats()} | {:error, Error.t()}
  def stats(table) do
    try do
      size = :ets.info(table, :size)
      memory = :ets.info(table, :memory)

      # Get hit/miss stats
      {hits, misses} = get_hit_miss_stats(table)

      stats = %{
        name: table,
        size: size,
        memory: memory,
        hits: hits,
        misses: misses,
        created_at: get_table_creation_time(table)
      }

      {:ok, stats}
    rescue
      ArgumentError ->
        {:error,
         Error.cache_error(:table_not_found, "Cache table does not exist", %{table: table})}
    end
  end

  @doc """
  Checks if a cache table exists.
  """
  @spec table_exists?(table_name()) :: boolean()
  def table_exists?(table) do
    case :ets.whereis(table) do
      :undefined -> false
      _ -> true
    end
  end

  @doc """
  Gets information about all managed cache tables.
  """
  @spec get_all_stats() :: {:ok, [cache_stats()]} | {:error, Error.t()}
  def get_all_stats do
    GenServer.call(__MODULE__, :get_all_stats)
  end

  @doc """
  Cleans up expired entries from all cache tables.
  """
  @spec cleanup_expired() :: :ok
  def cleanup_expired do
    GenServer.cast(__MODULE__, :cleanup_expired)
  end

  @doc """
  Gets or sets a cache value with a fallback function.
  """
  @spec get_or_set(table_name(), cache_key(), (-> cache_value()), ttl_seconds() | nil) ::
          {:ok, cache_value()} | {:error, Error.t()}
  def get_or_set(table, key, fallback_fn, ttl \\ nil) do
    case get(table, key) do
      {:ok, value} ->
        {:ok, value}

      {:error, _} ->
        try do
          value = fallback_fn.()

          case ttl do
            nil -> put(table, key, value)
            ttl_seconds -> put_with_ttl(table, key, value, ttl_seconds)
          end

          {:ok, value}
        rescue
          error ->
            {:error,
             Error.cache_error(:fallback_error, "Cache fallback function failed", %{
               error: inspect(error)
             })}
        end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @spec create_table_specs([table_name()]) :: [table_spec()]
  defp create_table_specs(table_names) do
    Enum.map(table_names, fn table_name ->
      {table_name, [:named_table, :set, :public], "Cache table for #{table_name}"}
    end)
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  @impl GenServer
  def init(table_specs) do
    Logger.info("Initializing cache manager", table_count: length(table_specs))

    created_tables =
      Enum.map(table_specs, fn {name, options, description} ->
        case create_table_if_not_exists(name, options) do
          :ok ->
            Logger.debug("Created cache table", name: name, description: description)
            initialize_table_stats(name)
            {name, options, description, :created}

          {:error, reason} ->
            Logger.error("Failed to create cache table",
              name: name,
              description: description,
              error: reason
            )

            {name, options, description, {:error, reason}}
        end
      end)

    # Initialize global counters
    initialize_counters()

    # Schedule periodic cleanup
    schedule_cleanup()

    state = %{
      tables: created_tables,
      created_at: Clock.now()
    }

    Logger.info("Cache manager initialized",
      total_tables: length(table_specs),
      successful_tables: count_successful_tables(created_tables)
    )

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_all_stats, _from, state) do
    all_stats =
      state.tables
      |> Enum.filter(fn {_name, _options, _description, status} -> status == :created end)
      |> Enum.map(fn {name, _options, _description, _status} ->
        case stats(name) do
          {:ok, stats} -> stats
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, {:ok, all_stats}, state}
  end

  @impl GenServer
  def handle_cast(:cleanup_expired, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:cleanup_expired, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec create_table_if_not_exists(table_name(), [atom()]) :: :ok | {:error, term()}
  defp create_table_if_not_exists(table_name, options) do
    with :undefined <- :ets.whereis(table_name),
         ^table_name <- safe_create_table(table_name, options) do
      :ok
    else
      # Table creation failed
      {:error, reason} -> {:error, reason}
      # Table already exists (not :undefined)
      _existing_table -> :ok
    end
  end

  @spec safe_create_table(table_name(), [atom()]) :: table_name() | {:error, term()}
  defp safe_create_table(table_name, options) do
    try do
      :ets.new(table_name, options)
    rescue
      error -> {:error, {:exception, error}}
    catch
      error -> {:error, {:creation_failed, error}}
    end
  end

  @spec initialize_table_stats(table_name()) :: :ok
  defp initialize_table_stats(table_name) do
    if table_exists?(:cache_stats) do
      stats_key = :"#{table_name}_stats"
      # {hits, misses, created_at}
      initial_stats = {0, 0, Clock.now()}
      :ets.insert(:cache_stats, {stats_key, initial_stats})
    end

    :ok
  end

  @spec initialize_counters() :: :ok
  defp initialize_counters do
    if table_exists?(:counters) do
      case :ets.lookup(:counters, :killmail_seq) do
        [] ->
          :ets.insert(:counters, {:killmail_seq, 0})
          Logger.debug("Initialized killmail sequence counter")

        _ ->
          Logger.debug("Killmail sequence counter already exists")
      end
    end

    :ok
  end

  @spec increment_stat(table_name(), :hits | :misses) :: :ok
  defp increment_stat(table_name, stat_type) do
    if table_exists?(:cache_stats) do
      stats_key = :"#{table_name}_stats"

      case :ets.lookup(:cache_stats, stats_key) do
        [{^stats_key, {hits, misses, created_at}}] ->
          new_stats =
            case stat_type do
              :hits -> {hits + 1, misses, created_at}
              :misses -> {hits, misses + 1, created_at}
            end

          :ets.insert(:cache_stats, {stats_key, new_stats})

        [] ->
          # Initialize if not exists
          initial_stats =
            case stat_type do
              :hits -> {1, 0, Clock.now()}
              :misses -> {0, 1, Clock.now()}
            end

          :ets.insert(:cache_stats, {stats_key, initial_stats})
      end
    end

    :ok
  end

  @spec get_hit_miss_stats(table_name()) :: {non_neg_integer(), non_neg_integer()}
  defp get_hit_miss_stats(table_name) do
    if table_exists?(:cache_stats) do
      stats_key = :"#{table_name}_stats"

      case :ets.lookup(:cache_stats, stats_key) do
        [{^stats_key, {hits, misses, _created_at}}] -> {hits, misses}
        [] -> {0, 0}
      end
    else
      {0, 0}
    end
  end

  @spec get_table_creation_time(table_name()) :: DateTime.t()
  defp get_table_creation_time(table_name) do
    if table_exists?(:cache_stats) do
      stats_key = :"#{table_name}_stats"

      case :ets.lookup(:cache_stats, stats_key) do
        [{^stats_key, {_hits, _misses, created_at}}] -> created_at
        [] -> Clock.now()
      end
    else
      Clock.now()
    end
  end

  @spec cleanup_expired_entries() :: :ok
  defp cleanup_expired_entries do
    current_time = Clock.now_milliseconds()

    # Get all tables that might have TTL entries
    tables_to_clean = [:killmails, :systems, :ship_types, :esi_cache]

    Enum.each(tables_to_clean, fn table ->
      if table_exists?(table) do
        # Find and delete expired entries
        expired_keys =
          :ets.foldl(
            fn
              {key, _value, expires_at}, acc
              when is_integer(expires_at) and expires_at < current_time ->
                [key | acc]

              _entry, acc ->
                acc
            end,
            [],
            table
          )

        Enum.each(expired_keys, fn key ->
          :ets.delete(table, key)
        end)

        if length(expired_keys) > 0 do
          Logger.debug("Cleaned up expired cache entries",
            table: table,
            expired_count: length(expired_keys)
          )
        end
      end
    end)

    :ok
  end

  @spec schedule_cleanup() :: reference()
  defp schedule_cleanup do
    # 5 minutes default
    cleanup_interval = Config.get(:cache_cleanup_interval_ms, 300_000)
    Process.send_after(self(), :cleanup_expired, cleanup_interval)
  end

  @spec count_successful_tables([tuple()]) :: non_neg_integer()
  defp count_successful_tables(tables) do
    Enum.count(tables, fn {_name, _options, _description, status} ->
      status == :created
    end)
  end

  # ============================================================================
  # Advanced Cache Functions
  # ============================================================================

  @doc """
  Gets all killmail IDs for a specific system.

  ## Parameters
  - `system_id` - The system ID to get killmails for

  ## Returns
  - `{:ok, [killmail_id]}` - List of killmail IDs for the system
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, killmail_ids} = Cache.get_killmails_for_system(30000142)
  ```
  """
  @spec get_killmails_for_system(integer()) :: {:ok, [integer()]} | {:error, Error.t()}
  def get_killmails_for_system(system_id) when is_integer(system_id) and system_id > 0 do
    if table_exists?(:system_killmails) do
      case :ets.lookup(:system_killmails, system_id) do
        [{^system_id, killmail_ids}] when is_list(killmail_ids) ->
          {:ok, killmail_ids}

        [] ->
          {:ok, []}

        other ->
          Logger.warning("Invalid system_killmails entry format",
            system_id: system_id,
            entry: inspect(other)
          )

          {:ok, []}
      end
    else
      {:error, Error.cache_error(:table_missing, "system_killmails table not available")}
    end
  end

  def get_killmails_for_system(invalid_id) do
    {:error, Error.validation_error(:invalid_format, "Invalid system ID: #{inspect(invalid_id)}")}
  end

  @doc """
  Associates a killmail ID with a system.

  ## Parameters
  - `system_id` - The system ID
  - `killmail_id` - The killmail ID to associate

  ## Returns
  - `:ok` - On successful association
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  :ok = Cache.add_system_killmail(30000142, 12345)
  ```
  """
  @spec add_system_killmail(integer(), integer()) :: :ok | {:error, Error.t()}
  def add_system_killmail(system_id, killmail_id)
      when is_integer(system_id) and system_id > 0 and is_integer(killmail_id) do
    if table_exists?(:system_killmails) do
      case :ets.lookup(:system_killmails, system_id) do
        [] ->
          :ets.insert(:system_killmails, {system_id, [killmail_id]})
          :ok

        [{^system_id, existing_ids}] when is_list(existing_ids) ->
          # Ensure we don't add duplicates
          if killmail_id not in existing_ids do
            new_ids = [killmail_id | existing_ids]
            :ets.insert(:system_killmails, {system_id, new_ids})
          end

          :ok

        _other ->
          # Fix corrupted entry
          :ets.insert(:system_killmails, {system_id, [killmail_id]})
          :ok
      end
    else
      {:error, Error.cache_error(:table_missing, "system_killmails table not available")}
    end
  end

  def add_system_killmail(invalid_system_id, invalid_killmail_id) do
    {:error,
     Error.validation_error(
       :invalid_format,
       "Invalid parameters: system_id=#{inspect(invalid_system_id)}, killmail_id=#{inspect(invalid_killmail_id)}"
     )}
  end

  @doc """
  Adds a system to the active systems list.

  Active systems are tracked for background processing by the preloader.

  ## Parameters
  - `system_id` - The system ID to mark as active

  ## Returns
  - `{:ok, :added}` - On successful addition
  - `{:ok, :already_exists}` - If already in active list
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, :added} = Cache.add_active_system(30000142)
  ```
  """
  @spec add_active_system(integer()) :: {:ok, :added | :already_exists} | {:error, Error.t()}
  def add_active_system(system_id) when is_integer(system_id) and system_id > 0 do
    if table_exists?(:active_systems) do
      case :ets.lookup(:active_systems, system_id) do
        [] ->
          :ets.insert(:active_systems, {system_id, Clock.now()})
          {:ok, :added}

        [{^system_id, _timestamp}] ->
          {:ok, :already_exists}
      end
    else
      {:error, Error.cache_error(:table_missing, "active_systems table not available")}
    end
  end

  def add_active_system(invalid_id) do
    {:error, Error.validation_error(:invalid_format, "Invalid system ID: #{inspect(invalid_id)}")}
  end

  @doc """
  Gets all active system IDs.

  ## Returns
  - `{:ok, [system_id]}` - List of active system IDs
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, system_ids} = Cache.get_active_systems()
  ```
  """
  @spec get_active_systems() :: {:ok, [integer()]} | {:error, Error.t()}
  def get_active_systems do
    if table_exists?(:active_systems) do
      system_ids =
        :ets.tab2list(:active_systems)
        |> Enum.map(fn {system_id, _timestamp} -> system_id end)
        |> Enum.sort()

      {:ok, system_ids}
    else
      {:error, Error.cache_error(:table_missing, "active_systems table not available")}
    end
  end

  @doc """
  Checks if a system was recently fetched based on a time threshold.

  ## Parameters
  - `system_id` - The system ID to check
  - `threshold_hours` - Hours threshold (default: 1 hour)

  ## Returns
  - `{:ok, true}` - If system was recently fetched
  - `{:ok, false}` - If system was not recently fetched or no timestamp exists
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, false} = Cache.system_recently_fetched?(30000142)
  {:ok, true} = Cache.system_recently_fetched?(30000142, 24)
  ```
  """
  @spec system_recently_fetched?(integer(), pos_integer()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def system_recently_fetched?(system_id, threshold_hours \\ 1)

  def system_recently_fetched?(system_id, threshold_hours)
      when is_integer(system_id) and system_id > 0 and is_integer(threshold_hours) do
    case get_system_fetch_timestamp(system_id) do
      {:ok, timestamp} ->
        cutoff_time = Clock.now() |> DateTime.add(-threshold_hours * 3600, :second)
        is_recent = DateTime.compare(timestamp, cutoff_time) == :gt
        {:ok, is_recent}

      {:error, %Error{type: :not_found}} ->
        {:ok, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def system_recently_fetched?(invalid_id, _threshold_hours) do
    {:error, Error.validation_error(:invalid_format, "Invalid system ID: #{inspect(invalid_id)}")}
  end

  @doc """
  Sets the fetch timestamp for a system.

  ## Parameters
  - `system_id` - The system ID
  - `timestamp` - The timestamp (defaults to current time)

  ## Returns
  - `{:ok, :set}` - On successful update
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, :set} = Cache.set_system_fetch_timestamp(30000142)
  {:ok, :set} = Cache.set_system_fetch_timestamp(30000142, ~U[2023-01-01 12:00:00Z])
  ```
  """
  @spec set_system_fetch_timestamp(integer(), DateTime.t() | nil) ::
          {:ok, :set} | {:error, Error.t()}
  def set_system_fetch_timestamp(system_id, timestamp \\ nil)

  def set_system_fetch_timestamp(system_id, timestamp)
      when is_integer(system_id) and system_id > 0 do
    actual_timestamp = timestamp || Clock.now()

    if table_exists?(:system_fetch_timestamps) do
      :ets.insert(:system_fetch_timestamps, {system_id, actual_timestamp})
      {:ok, :set}
    else
      {:error, Error.cache_error(:table_missing, "system_fetch_timestamps table not available")}
    end
  end

  def set_system_fetch_timestamp(invalid_id, _timestamp) do
    {:error, Error.validation_error(:invalid_format, "Invalid system ID: #{inspect(invalid_id)}")}
  end

  @doc """
  Gets the fetch timestamp for a system.

  ## Parameters
  - `system_id` - The system ID

  ## Returns
  - `{:ok, timestamp}` - The fetch timestamp
  - `{:error, :not_found}` - If no timestamp exists
  - `{:error, reason}` - On other failures

  ## Examples

  ```elixir
  {:ok, timestamp} = Cache.get_system_fetch_timestamp(30000142)
  {:error, %Error{type: :not_found}} = Cache.get_system_fetch_timestamp(99999)
  ```
  """
  @spec get_system_fetch_timestamp(integer()) :: {:ok, DateTime.t()} | {:error, Error.t()}
  def get_system_fetch_timestamp(system_id) when is_integer(system_id) and system_id > 0 do
    if table_exists?(:system_fetch_timestamps) do
      case :ets.lookup(:system_fetch_timestamps, system_id) do
        [{^system_id, timestamp}] when is_struct(timestamp, DateTime) ->
          {:ok, timestamp}

        [] ->
          {:error,
           Error.not_found_error("No fetch timestamp found for system", %{system_id: system_id})}

        other ->
          Logger.warning("Invalid system_fetch_timestamps entry format",
            system_id: system_id,
            entry: inspect(other)
          )

          {:error, Error.cache_error(:invalid_data, "Corrupted timestamp data")}
      end
    else
      {:error, Error.cache_error(:table_missing, "system_fetch_timestamps table not available")}
    end
  end

  def get_system_fetch_timestamp(invalid_id) do
    {:error, Error.validation_error(:invalid_format, "Invalid system ID: #{inspect(invalid_id)}")}
  end

  @doc """
  Increments the kill count for a system.

  ## Parameters
  - `system_id` - The system ID

  ## Returns
  - `{:ok, new_count}` - The new count after incrementing
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, 1} = Cache.increment_system_kill_count(30000142)
  {:ok, 2} = Cache.increment_system_kill_count(30000142)
  ```
  """
  @spec increment_system_kill_count(integer()) :: {:ok, integer()} | {:error, Error.t()}
  def increment_system_kill_count(system_id) when is_integer(system_id) and system_id > 0 do
    if table_exists?(:system_kill_counts) do
      try do
        new_count = :ets.update_counter(:system_kill_counts, system_id, {2, 1}, {system_id, 0})
        {:ok, new_count}
      rescue
        ArgumentError ->
          {:error, Error.cache_error(:update_failed, "Failed to increment system kill count")}
      end
    else
      {:error, Error.cache_error(:table_missing, "system_kill_counts table not available")}
    end
  end

  def increment_system_kill_count(invalid_id) do
    {:error, Error.validation_error(:invalid_format, "Invalid system ID: #{inspect(invalid_id)}")}
  end

  @doc """
  Gets the kill count for a system.

  ## Parameters
  - `system_id` - The system ID

  ## Returns
  - `{:ok, count}` - The current kill count
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, 5} = Cache.get_system_kill_count(30000142)
  {:ok, 0} = Cache.get_system_kill_count(99999)
  ```
  """
  @spec get_system_kill_count(integer()) :: {:ok, integer()} | {:error, Error.t()}
  def get_system_kill_count(system_id) when is_integer(system_id) and system_id > 0 do
    if table_exists?(:system_kill_counts) do
      case :ets.lookup(:system_kill_counts, system_id) do
        [{^system_id, count}] when is_integer(count) ->
          {:ok, count}

        [] ->
          {:ok, 0}

        other ->
          Logger.warning("Invalid system_kill_counts entry format",
            system_id: system_id,
            entry: inspect(other)
          )

          {:ok, 0}
      end
    else
      {:error, Error.cache_error(:table_missing, "system_kill_counts table not available")}
    end
  end

  def get_system_kill_count(invalid_id) do
    {:error, Error.validation_error(:invalid_format, "Invalid system ID: #{inspect(invalid_id)}")}
  end
end
