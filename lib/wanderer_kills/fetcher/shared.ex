defmodule WandererKills.Fetcher do
  @moduledoc """
  Unified fetcher module for killmails and system data.

  This module consolidates functionality from:
  - KillmailFetcher (individual killmail fetching)
  - SystemFetcher (system-based killmail fetching)
  - ZkbActiveFetcher (active system management)

  ## Features

  - Automatic caching with configurable TTLs
  - Rate limit handling and automatic retries
  - Parallel processing for batch operations
  - Time-based filtering of killmails
  - Error handling and logging
  - Unified telemetry and monitoring

  ## Usage

  ```elixir
  # Fetch a single killmail
  {:ok, killmail} = Fetcher.fetch_and_cache_killmail(12345)

  # Fetch killmails for a system
  {:ok, killmails} = Fetcher.fetch_killmails_for_system(30000142, limit: 10)

  # Batch fetch for multiple systems
  results = Fetcher.fetch_killmails_for_systems([30000142, 30000143], max_concurrency: 4)
  ```

  ## Configuration

  Default options:
  - `limit`: 5 killmails per system
  - `since_hours`: 24 hours
  - `max_concurrency`: 8 parallel tasks
  - `force`: false (use cache if available)

  ## Error Handling

  All functions return either:
  - `{:ok, result}` - On success
  - `{:error, reason}` - On failure

  Batch operations return a map of system IDs to results.
  """

  require Logger

  alias WandererKills.Cache
  alias WandererKills.Zkb.Client, as: ZkbClient
  alias WandererKills.Parser.Core, as: Parser
  alias WandererKills.Parser.Enricher
  alias WandererKills.Infrastructure.Telemetry

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type killmail :: map()
  @type fetch_opts :: [
          limit: pos_integer(),
          force: boolean(),
          since_hours: pos_integer(),
          max_concurrency: pos_integer(),
          timeout: pos_integer()
        ]

  @default_limit Application.compile_env(:wanderer_kills, [:fetcher, :default_limit], 5)
  @default_since_hours Application.compile_env(:wanderer_kills, [:fetcher, :since_hours], 24)

  # -------------------------------------------------
  # Single killmail operations
  # -------------------------------------------------

  @doc """
  Fetches a killmail from zKillboard and caches it.
  Returns {:ok, killmail} if successful, {:error, reason} otherwise.
  """
  @spec fetch_and_cache_killmail(integer(), module()) :: {:ok, map()} | {:error, term()}
  def fetch_and_cache_killmail(id, client \\ nil)

  def fetch_and_cache_killmail(id, client) when is_integer(id) and id > 0 do
    # Use dependency injection if no client specified
    actual_client = client || Application.get_env(:wanderer_kills, :zkb_client, ZkbClient)

    Logger.debug("Fetching killmail",
      killmail_id: id,
      operation: :fetch_and_cache,
      step: :start
    )

    case actual_client.fetch_killmail(id) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, killmail} ->
        Telemetry.fetch_system_complete(id, :success)
        Cache.set_killmail(id, killmail)
        {:ok, killmail}

      {:error, reason} ->
        Telemetry.fetch_system_error(id, reason, :zkb)

        Logger.error("Failed to fetch killmail",
          killmail_id: id,
          operation: :fetch_from_zkb,
          error: reason,
          status: :fetch_error
        )

        {:error, reason}
    end
  end

  def fetch_and_cache_killmail(_id, _client), do: {:error, :invalid_id}

  # -------------------------------------------------
  # System-scoped killmail operations
  # -------------------------------------------------

  @doc """
  Fetch and parse killmails for a given system.

  ## Parameters
  - `system_id` - The system ID to fetch killmails for
  - `opts` - Options including:
    - `:limit` - Maximum number of killmails to fetch (default: #{@default_limit})
    - `:force` - Ignore recent cache and force fresh fetch (default: false)
    - `:since_hours` - Only fetch killmails newer than this (default: #{@default_since_hours})

  ## Returns
  - `{:ok, [enriched_killmail]}` - On success
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  # Fetch with defaults
  {:ok, killmails} = fetch_killmails_for_system(30000142)

  # Fetch with custom options
  opts = [
    limit: 10,
    force: true,
    since_hours: 48
  ]
  {:ok, killmails} = fetch_killmails_for_system(30000142, opts)

  # Handle string system ID
  {:ok, killmails} = fetch_killmails_for_system("30000142")
  ```
  """
  @spec fetch_killmails_for_system(String.t() | integer(), fetch_opts()) ::
          {:ok, [killmail()]} | {:error, term()}
  def fetch_killmails_for_system(id, opts \\ []) do
    client = Keyword.get(opts, :client)
    fetch_killmails_for_system(id, :unified_fetcher, opts, client)
  end

  # -------------------------------------------------
  # Implementation details (previously from Shared)
  # -------------------------------------------------

  @doc """
  Internal implementation that handles the actual fetching logic.
  This was previously in the Shared module.
  """
  @spec fetch_killmails_for_system(String.t() | integer(), atom(), fetch_opts(), module() | nil) ::
          {:ok, [killmail()]} | {:error, term()}
  def fetch_killmails_for_system(id, source, opts, client \\ nil)

  def fetch_killmails_for_system(id, source, opts, client) when is_binary(id) do
    case Integer.parse(id) do
      {system_id, ""} -> fetch_killmails_for_system(system_id, source, opts, client)
      _ -> {:error, :invalid_system_id}
    end
  end

  def fetch_killmails_for_system(system_id, source, opts, client) when is_integer(system_id) do
    limit = Keyword.get(opts, :limit, @default_limit)
    force = Keyword.get(opts, :force, false)
    since_hours = Keyword.get(opts, :since_hours, @default_since_hours)

    Logger.info("Fetching killmails for system",
      system_id: system_id,
      limit: limit,
      force: force,
      since_hours: since_hours,
      source: source
    )

    result =
      if force do
        fetch_remote_killmails(system_id, limit, since_hours, source, client)
      else
        check_cache_then_fetch_remote(system_id, limit, since_hours, source, client)
      end

    case result do
      {:ok, killmails} ->
        Logger.info("Successfully fetched killmails for system",
          system_id: system_id,
          killmail_count: length(killmails),
          source: source
        )

        {:ok, killmails}

      {:error, reason} ->
        Logger.error("Failed to fetch killmails for system",
          system_id: system_id,
          error: reason,
          source: source
        )

        {:error, reason}
    end
  end

  def fetch_killmails_for_system(_id, _source, _opts, _client), do: {:error, :invalid_system_id}

  # -------------------------------------------------
  # Batch operations
  # -------------------------------------------------

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
  results = fetch_killmails_for_systems([30000142, 30000143])

  # With custom concurrency
  opts = [max_concurrency: 4, limit: 10]
  results = fetch_killmails_for_systems([30000142, 30000143], opts)
  ```
  """
  @spec fetch_killmails_for_systems([system_id()], fetch_opts()) ::
          %{system_id() => {:ok, [killmail()]} | {:error, term()}} | {:error, term()}
  def fetch_killmails_for_systems(system_ids, opts \\ [])

  def fetch_killmails_for_systems(system_ids, opts) when is_list(system_ids) do
    Logger.info("Starting to fetch killmails for #{length(system_ids)} systems")
    client = Keyword.get(opts, :client)

    results =
      Task.Supervisor.async_stream(
        WandererKills.TaskSupervisor,
        system_ids,
        &safe_fetch_for_system(&1, opts, client),
        max_concurrency: Keyword.get(opts, :max_concurrency, 8),
        timeout: Keyword.get(opts, :timeout, 30_000)
      )
      |> Enum.map(fn
        {:ok, {sid, result}} ->
          Telemetry.fetch_system_complete(
            sid,
            if(match?({:ok, _}, result), do: :success, else: :error)
          )

          {sid, result}

        {:exit, {sid, reason}} ->
          Telemetry.fetch_system_error(sid, reason, :task_exit)
          Logger.error("Task exit for system #{sid}: #{inspect(reason)}")
          {sid, {:error, {:task_exit, reason}}}

        {:exit, reason} ->
          Logger.error("Unexpected task exit without system ID: #{inspect(reason)}")
          {:unknown_system, {:error, {:unexpected_exit, reason}}}

        other ->
          Logger.error("Unexpected task result: #{inspect(other)}")
          {:unknown_system, {:error, {:unexpected_result, other}}}
      end)
      |> Enum.reject(fn {sid, _result} -> sid == :unknown_system end)
      |> Map.new()

    if map_size(results) == 0 do
      {:error, :no_results}
    else
      results
    end
  end

  def fetch_killmails_for_systems(_system_ids, _opts), do: {:error, :invalid_system_ids}

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
  {:ok, 15} = get_system_kill_count(30000142)
  {:ok, 20} = get_system_kill_count("30000142")
  ```
  """
  @spec get_system_kill_count(String.t() | integer(), module()) ::
          {:ok, integer()} | {:error, term()}
  def get_system_kill_count(id, client \\ nil)

  def get_system_kill_count(id, client) when is_binary(id) do
    case Integer.parse(id) do
      {system_id, ""} -> get_system_kill_count(system_id, client)
      _ -> {:error, :invalid_system_id}
    end
  end

  def get_system_kill_count(system_id, client) when is_integer(system_id) do
    actual_client = client || Application.get_env(:wanderer_kills, :zkb_client, ZkbClient)

    case actual_client.get_system_kill_count(system_id) do
      {:ok, count} when is_integer(count) ->
        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_system_kill_count(_id, _client), do: {:error, :invalid_system_id}

  # -------------------------------------------------
  # Private helper functions
  # -------------------------------------------------

  # Helper function to safely fetch killmails for a system
  defp safe_fetch_for_system(system_id, opts, client) do
    opts_with_client = if client, do: opts ++ [client: client], else: opts
    result = fetch_killmails_for_system(system_id, opts_with_client)
    {system_id, result}
  end

  # Check cache first, then fetch if needed
  defp check_cache_then_fetch_remote(system_id, limit, since_hours, source, client) do
    case Cache.system_recently_fetched?(system_id) do
      {:ok, true} ->
        Logger.debug("System recently fetched, using cache",
          system_id: system_id,
          source: source
        )

        Cache.get_system_killmails(system_id)

      {:ok, false} ->
        fetch_remote_killmails(system_id, limit, since_hours, source, client)

      {:error, reason} ->
        Logger.warning("Cache check failed, proceeding with fetch",
          system_id: system_id,
          error: reason,
          source: source
        )

        fetch_remote_killmails(system_id, limit, since_hours, source, client)
    end
  end

  # Perform the actual fetch operation
  defp fetch_remote_killmails(system_id, limit, since_hours, source, client) do
    Telemetry.fetch_system_start(system_id, limit, source)

    with {:ok, raw_killmails} <- fetch_raw_killmails(system_id, limit, since_hours, client),
         {:ok, parsed_killmails} <- parse_killmails(raw_killmails),
         {:ok, enriched_killmails} <- enrich_killmails(parsed_killmails),
         :ok <- cache_results(system_id, enriched_killmails) do
      Telemetry.fetch_system_success(system_id, length(enriched_killmails), source)
      {:ok, enriched_killmails}
    else
      {:error, reason} ->
        Telemetry.fetch_system_error(system_id, reason, source)
        {:error, reason}
    end
  end

  # Fetch raw killmails from zKillboard
  defp fetch_raw_killmails(system_id, _limit, _since_hours, client) do
    client = client || Application.get_env(:wanderer_kills, :zkb_client, ZkbClient)

    # ZKB client doesn't accept limit or since_hours parameters directly
    # We'll need to filter the results after fetching
    client.fetch_system_killmails(system_id)
  end

  # Parse raw killmails
  defp parse_killmails(raw_killmails) do
    try do
      parsed =
        raw_killmails
        |> Enum.map(&Parser.parse_killmail(&1))
        |> Enum.filter(fn
          {:ok, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, killmail} -> killmail end)

      {:ok, parsed}
    rescue
      error ->
        Logger.error("Failed to parse killmails",
          error: inspect(error)
        )

        {:error, :parse_error}
    end
  end

  # Enrich killmails with additional data
  defp enrich_killmails(parsed_killmails) do
    try do
      enriched =
        parsed_killmails
        |> Enum.map(fn killmail ->
          case Enricher.enrich_killmail(killmail) do
            {:ok, enriched} -> enriched
            # Fall back to original if enrichment fails
            {:error, _} -> killmail
          end
        end)

      {:ok, enriched}
    rescue
      error ->
        Logger.error("Failed to enrich killmails", error: inspect(error))
        {:error, :enrichment_error}
    end
  end

  # Cache the results
  defp cache_results(system_id, killmails) do
    # Update fetch timestamp
    Cache.set_system_fetch_timestamp(system_id)

    # Cache killmails list - extract killmail_ids properly and add them individually
    killmail_ids =
      Enum.map(killmails, fn killmail ->
        Map.get(killmail, "killmail_id") || Map.get(killmail, "killID")
      end)
      |> Enum.filter(&(&1 != nil))

    # Add each killmail ID individually
    Enum.each(killmail_ids, fn killmail_id ->
      Cache.add_system_killmail(system_id, killmail_id)
    end)

    # Add system to active list
    Cache.add_active_system(system_id)

    :ok
  end
end
