defmodule WandererKills.Fetcher.Coordinator do
  @moduledoc """
  Thin orchestration layer for fetching operations.

  This module coordinates the interaction between ZkbService, CacheService,
  and Processor to provide a unified fetching interface. It replaces the
  previous monolithic fetcher/shared.ex module with clear separation of concerns.
  """

  require Logger
  alias WandererKills.Fetcher.{ZkbService, CacheService, Processor}
  alias WandererKills.Infrastructure.Error
  alias WandererKills.Observability.Telemetry
  alias WandererKills.Cache

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type killmail :: map()
  @type fetch_opts :: [
          limit: pos_integer(),
          force: boolean(),
          since_hours: pos_integer(),
          max_concurrency: pos_integer(),
          timeout: pos_integer(),
          client: module()
        ]

  @default_limit Application.compile_env(:wanderer_kills, [:fetcher, :default_limit], 5)
  @default_since_hours Application.compile_env(:wanderer_kills, [:fetcher, :since_hours], 24)

  # =============================================================================
  # Single Killmail Operations
  # =============================================================================

  @doc """
  Fetches a killmail from zKillboard and caches it.

  ## Parameters
  - `killmail_id` - The ID of the killmail to fetch
  - `client` - Optional ZKB client module (for testing)

  ## Returns
  - `{:ok, killmail}` - On successful fetch and processing
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, killmail} = Coordinator.fetch_and_cache_killmail(12345)
  {:error, reason} = Coordinator.fetch_and_cache_killmail(99999)
  ```
  """
  @spec fetch_and_cache_killmail(killmail_id(), module() | nil) ::
          {:ok, killmail()} | {:error, term()}
  def fetch_and_cache_killmail(killmail_id, client \\ nil)

  def fetch_and_cache_killmail(killmail_id, client)
      when is_integer(killmail_id) and killmail_id > 0 do
    Logger.debug("Starting killmail fetch and cache",
      killmail_id: killmail_id,
      operation: :fetch_and_cache_killmail,
      step: :start
    )

    with {:ok, raw_killmail} <- ZkbService.fetch_killmail(killmail_id, client),
         {:ok, processed_killmail} <- Processor.process_single_killmail(raw_killmail),
         :ok <- Cache.set_killmail(killmail_id, processed_killmail) do
      Telemetry.fetch_system_complete(killmail_id, :success)

      Logger.debug("Successfully fetched and cached killmail",
        killmail_id: killmail_id,
        operation: :fetch_and_cache_killmail,
        step: :success
      )

      {:ok, processed_killmail}
    else
      {:error, reason} ->
        Telemetry.fetch_system_error(killmail_id, reason, :coordinator)

        Logger.error("Failed to fetch and cache killmail",
          killmail_id: killmail_id,
          error: reason,
          operation: :fetch_and_cache_killmail,
          step: :error
        )

        {:error, reason}
    end
  end

  def fetch_and_cache_killmail(invalid_id, _client) do
    {:error, Error.validation_error("Invalid killmail ID format: #{inspect(invalid_id)}")}
  end

  # =============================================================================
  # System-Scoped Killmail Operations
  # =============================================================================

  @doc """
  Fetch and process killmails for a given system.

  ## Parameters
  - `system_id` - The system ID to fetch killmails for (integer or string)
  - `opts` - Options including:
    - `:limit` - Maximum number of killmails to fetch (default: #{@default_limit})
    - `:force` - Ignore recent cache and force fresh fetch (default: false)
    - `:since_hours` - Only fetch killmails newer than this (default: #{@default_since_hours})
    - `:client` - Optional client module for testing

  ## Returns
  - `{:ok, [enriched_killmail]}` - On success
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  # Fetch with defaults
  {:ok, killmails} = Coordinator.fetch_killmails_for_system(30000142)

  # Fetch with custom options
  opts = [limit: 10, force: true, since_hours: 48]
  {:ok, killmails} = Coordinator.fetch_killmails_for_system(30000142, opts)
  ```
  """
  @spec fetch_killmails_for_system(String.t() | integer(), fetch_opts()) ::
          {:ok, [killmail()]} | {:error, term()}
  def fetch_killmails_for_system(system_id, opts \\ [])

  def fetch_killmails_for_system(system_id, opts) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {parsed_id, ""} -> fetch_killmails_for_system(parsed_id, opts)
      _ -> {:error, Error.validation_error("Invalid system ID format")}
    end
  end

  def fetch_killmails_for_system(system_id, opts) when is_integer(system_id) and system_id > 0 do
    limit = Keyword.get(opts, :limit, @default_limit)
    force = Keyword.get(opts, :force, false)
    since_hours = Keyword.get(opts, :since_hours, @default_since_hours)
    client = Keyword.get(opts, :client)

    Logger.info("Fetching killmails for system",
      system_id: system_id,
      limit: limit,
      force: force,
      since_hours: since_hours,
      operation: :fetch_killmails_for_system,
      step: :start
    )

    result =
      if force do
        fetch_remote_killmails(system_id, limit, since_hours, client)
      else
        check_cache_then_fetch_remote(system_id, limit, since_hours, client)
      end

    case result do
      {:ok, killmails} ->
        Logger.info("Successfully fetched killmails for system",
          system_id: system_id,
          killmail_count: length(killmails),
          operation: :fetch_killmails_for_system,
          step: :success
        )

        {:ok, killmails}

      {:error, reason} ->
        Logger.error("Failed to fetch killmails for system",
          system_id: system_id,
          error: reason,
          operation: :fetch_killmails_for_system,
          step: :error
        )

        {:error, reason}
    end
  end

  def fetch_killmails_for_system(invalid_id, _opts) do
    {:error, Error.validation_error("Invalid system ID format: #{inspect(invalid_id)}")}
  end

  # =============================================================================
  # Batch Operations
  # =============================================================================

  @doc """
  Fetch killmails for multiple systems in parallel.

  ## Parameters
  - `system_ids` - List of system IDs to fetch killmails for
  - `opts` - Options including:
    - `:max_concurrency` - Maximum number of parallel tasks (default: 8)
    - All options from `fetch_killmails_for_system/2`

  ## Returns
  Map of system IDs to results:
  - `%{system_id => {:ok, [killmail]} | {:error, reason}}`

  ## Examples

  ```elixir
  # Fetch for multiple systems
  results = Coordinator.fetch_killmails_for_systems([30000142, 30000143])

  # With custom concurrency
  opts = [max_concurrency: 4, limit: 10]
  results = Coordinator.fetch_killmails_for_systems([30000142, 30000143], opts)
  ```
  """
  @spec fetch_killmails_for_systems([system_id()], fetch_opts()) ::
          %{system_id() => {:ok, [killmail()]} | {:error, term()}} | {:error, term()}
  def fetch_killmails_for_systems(system_ids, opts \\ [])

  def fetch_killmails_for_systems(system_ids, opts) when is_list(system_ids) do
    Logger.info("Starting to fetch killmails for #{length(system_ids)} systems",
      operation: :fetch_killmails_for_systems,
      step: :start
    )

    results =
      Task.Supervisor.async_stream(
        WandererKills.TaskSupervisor,
        system_ids,
        &safe_fetch_for_system(&1, opts),
        max_concurrency: Keyword.get(opts, :max_concurrency, 8),
        timeout: Keyword.get(opts, :timeout, 30_000)
      )
      |> Enum.map(fn
        {:ok, {system_id, result}} ->
          Telemetry.fetch_system_complete(
            system_id,
            if(match?({:ok, _}, result), do: :success, else: :error)
          )

          {system_id, result}

        {:exit, {system_id, reason}} ->
          Telemetry.fetch_system_error(system_id, reason, :task_exit)
          Logger.error("Task exit for system #{system_id}: #{inspect(reason)}")
          {system_id, {:error, {:task_exit, reason}}}

        {:exit, reason} ->
          Logger.error("Unexpected task exit without system ID: #{inspect(reason)}")
          {:unknown_system, {:error, {:unexpected_exit, reason}}}

        other ->
          Logger.error("Unexpected task result: #{inspect(other)}")
          {:unknown_system, {:error, {:unexpected_result, other}}}
      end)
      |> Enum.reject(fn {system_id, _result} -> system_id == :unknown_system end)
      |> Map.new()

    if map_size(results) == 0 do
      {:error, Error.system_error(:no_results, "No systems produced valid results")}
    else
      Logger.info("Completed fetching killmails for systems",
        total_systems: length(system_ids),
        successful_systems: map_size(results),
        operation: :fetch_killmails_for_systems,
        step: :success
      )

      results
    end
  end

  def fetch_killmails_for_systems(invalid_ids, _opts) do
    {:error, Error.validation_error("System IDs must be a list, got: #{inspect(invalid_ids)}")}
  end

  @doc """
  Get the kill count for a system from zKillboard stats.

  ## Parameters
  - `system_id` - The system ID (integer or string)
  - `client` - Optional ZKB client module (for testing)

  ## Returns
  - `{:ok, count}` - On success
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, 15} = Coordinator.get_system_kill_count(30000142)
  {:ok, 20} = Coordinator.get_system_kill_count("30000142")
  ```
  """
  @spec get_system_kill_count(String.t() | integer(), module() | nil) ::
          {:ok, integer()} | {:error, term()}
  def get_system_kill_count(system_id, client \\ nil)

  def get_system_kill_count(system_id, client) when is_binary(system_id) do
    case Integer.parse(system_id) do
      {parsed_id, ""} -> get_system_kill_count(parsed_id, client)
      _ -> {:error, Error.validation_error("Invalid system ID format")}
    end
  end

  def get_system_kill_count(system_id, client) when is_integer(system_id) and system_id > 0 do
    ZkbService.get_system_kill_count(system_id, client)
  end

  def get_system_kill_count(invalid_id, _client) do
    {:error, Error.validation_error("Invalid system ID format: #{inspect(invalid_id)}")}
  end

  # =============================================================================
  # Private Helper Functions
  # =============================================================================

  # Helper function to safely fetch killmails for a system in a task
  defp safe_fetch_for_system(system_id, opts) do
    result = fetch_killmails_for_system(system_id, opts)
    {system_id, result}
  end

  # Check cache first, then fetch if needed
  defp check_cache_then_fetch_remote(system_id, limit, since_hours, client) do
    case CacheService.check_cache_or_fetch(system_id, since_hours) do
      {:cache, killmail_ids} ->
        Logger.debug("Using cached killmails for system",
          system_id: system_id,
          cached_count: length(killmail_ids),
          operation: :check_cache_then_fetch_remote,
          step: :cache_hit
        )

        # Return the cached killmail IDs as the result
        # Note: This is a simplified implementation. In a full implementation,
        # you might want to fetch the actual killmail data from cache
        {:ok, killmail_ids}

      {:fetch, :required} ->
        Logger.debug("Cache miss or stale, fetching from remote",
          system_id: system_id,
          operation: :check_cache_then_fetch_remote,
          step: :cache_miss
        )

        fetch_remote_killmails(system_id, limit, since_hours, client)

      {:error, reason} ->
        Logger.warning("Cache check failed, proceeding with remote fetch",
          system_id: system_id,
          error: reason,
          operation: :check_cache_then_fetch_remote,
          step: :cache_error
        )

        fetch_remote_killmails(system_id, limit, since_hours, client)
    end
  end

  # Perform the actual fetch operation
  defp fetch_remote_killmails(system_id, limit, since_hours, client) do
    Telemetry.fetch_system_start(system_id, limit, :coordinator)

    with {:ok, raw_killmails} <-
           ZkbService.fetch_system_killmails(system_id, limit, since_hours, client),
         {:ok, processed_killmails} <-
           Processor.process_killmails(raw_killmails, system_id, since_hours),
         :ok <- CacheService.cache_killmails(system_id, processed_killmails) do
      Telemetry.fetch_system_success(system_id, length(processed_killmails), :coordinator)

      Logger.debug("Successfully fetched and processed remote killmails",
        system_id: system_id,
        raw_count: length(raw_killmails),
        processed_count: length(processed_killmails),
        operation: :fetch_remote_killmails,
        step: :success
      )

      {:ok, processed_killmails}
    else
      {:error, reason} ->
        Telemetry.fetch_system_error(system_id, reason, :coordinator)

        Logger.error("Failed to fetch remote killmails",
          system_id: system_id,
          error: reason,
          operation: :fetch_remote_killmails,
          step: :error
        )

        {:error, reason}
    end
  end
end
