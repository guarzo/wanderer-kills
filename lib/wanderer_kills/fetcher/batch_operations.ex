defmodule WandererKills.Fetcher.BatchOperations do
  @moduledoc """
  Batch operation utilities for killmail fetching.

  This module contains helper functions for managing batch operations, parallel
  processing, and coordination between single and batch fetchers. It separates
  the batch operation concerns from the main fetcher module.

  ## Features

  - Parallel processing with configurable concurrency
  - Task supervision and error handling
  - Result aggregation and mapping
  - Cache coordination for batch operations
  - Error handling and telemetry integration

  ## Usage

  ```elixir
  # Process multiple systems in parallel
  results = BatchOperations.process_systems_parallel(system_ids, fetch_fn, opts)

  # Safe processing with error handling
  {:ok, result} = BatchOperations.safe_process_system(system_id, fetch_fn)

  # Aggregate batch results
  summary = BatchOperations.aggregate_batch_results(results)
  ```
  """

  require Logger
  alias WandererKills.Observability.Telemetry

  @type system_id :: pos_integer()
  @type batch_result :: {:ok, term()} | {:error, term()}
  @type batch_results :: %{system_id() => batch_result()}
  @type fetch_function :: (system_id() -> batch_result())
  @type batch_opts :: [
          max_concurrency: pos_integer(),
          timeout: pos_integer(),
          error_handling: :continue | :fail_fast
        ]

  @default_max_concurrency 8
  @default_timeout 30_000

  @doc """
  Processes multiple systems in parallel using the provided fetch function.

  This is the main entry point for batch operations. It handles task supervision,
  error handling, and result aggregation.

  ## Parameters
  - `system_ids` - List of system IDs to process
  - `fetch_function` - Function to execute for each system
  - `opts` - Batch processing options

  ## Returns
  - `batch_results()` - Map of system IDs to results
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  fetch_fn = fn system_id ->
            WandererKills.Fetcher.Coordinator.fetch_killmails_for_system(system_id)
  end

  results = BatchOperations.process_systems_parallel([1001, 1002], fetch_fn)
  # => %{1001 => {:ok, killmails}, 1002 => {:error, reason}}
  ```
  """
  @spec process_systems_parallel([system_id()], fetch_function(), batch_opts()) ::
          batch_results() | {:error, term()}
  def process_systems_parallel(system_ids, fetch_function, opts \\ [])

  def process_systems_parallel(system_ids, fetch_function, opts)
      when is_list(system_ids) and is_function(fetch_function, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    Logger.info("Starting batch processing for systems",
      system_count: length(system_ids),
      max_concurrency: max_concurrency,
      timeout: timeout
    )

    start_time = System.monotonic_time(:millisecond)

    try do
      results =
        Task.Supervisor.async_stream(
          WandererKills.TaskSupervisor,
          system_ids,
          &safe_process_system(&1, fetch_function),
          max_concurrency: max_concurrency,
          timeout: timeout,
          on_timeout: :kill_task
        )
        |> process_task_results()

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      log_batch_completion(system_ids, results, duration)
      results
    rescue
      error ->
        Logger.error("Exception during batch processing",
          error: inspect(error),
          system_count: length(system_ids)
        )

        {:error, :batch_processing_exception}
    end
  end

  def process_systems_parallel([], _fetch_function, _opts), do: %{}

  def process_systems_parallel(_system_ids, _fetch_function, _opts),
    do: {:error, :invalid_parameters}

  @doc """
  Safely processes a single system with error handling and telemetry.

  This function wraps the fetch function with proper error handling and
  telemetry reporting for use in batch operations.

  ## Parameters
  - `system_id` - The system ID to process
  - `fetch_function` - Function to execute for the system

  ## Returns
  - `{system_id, result}` - Tuple of system ID and result
  """
  @spec safe_process_system(system_id(), fetch_function()) :: {system_id(), batch_result()}
  def safe_process_system(system_id, fetch_function) when is_integer(system_id) do
    Logger.debug("Processing system", system_id: system_id)

    start_time = System.monotonic_time(:millisecond)

    try do
      result = fetch_function.(system_id)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      case result do
        {:ok, _data} ->
          Telemetry.fetch_system_complete(system_id, :success)

          Logger.debug("Successfully processed system",
            system_id: system_id,
            duration_ms: duration
          )

          {system_id, result}

        {:error, reason} ->
          Telemetry.fetch_system_error(system_id, reason, :fetch_failed)

          Logger.warning("Failed to process system",
            system_id: system_id,
            error: reason,
            duration_ms: duration
          )

          {system_id, result}
      end
    rescue
      error ->
        Telemetry.fetch_system_error(system_id, error, :exception)

        Logger.error("Exception processing system",
          system_id: system_id,
          error: inspect(error)
        )

        {system_id, {:error, {:exception, error}}}
    catch
      kind, error ->
        Telemetry.fetch_system_error(system_id, error, :catch)

        Logger.error("Caught error processing system",
          system_id: system_id,
          kind: kind,
          error: inspect(error)
        )

        {system_id, {:error, {:caught, kind, error}}}
    end
  end

  @doc """
  Aggregates batch results and provides summary statistics.

  ## Parameters
  - `results` - Batch results map

  ## Returns
  Map containing aggregated statistics and categorized results
  """
  @spec aggregate_batch_results(batch_results()) :: map()
  def aggregate_batch_results(results) when is_map(results) do
    {successful, failed} =
      results
      |> Enum.split_with(fn {_system_id, result} -> match?({:ok, _}, result) end)

    successful_count = length(successful)
    failed_count = length(failed)
    total_count = successful_count + failed_count

    success_rate = if total_count > 0, do: successful_count / total_count * 100, else: 0

    %{
      total_systems: total_count,
      successful_systems: successful_count,
      failed_systems: failed_count,
      success_rate: Float.round(success_rate, 2),
      successful_results: Map.new(successful),
      failed_results: Map.new(failed),
      error_summary: summarize_errors(failed)
    }
  end

  @doc """
  Checks if a batch operation should continue based on current results.

  This can be used for implementing fail-fast behavior or other conditional
  logic in batch operations.

  ## Parameters
  - `results` - Current batch results
  - `opts` - Options including error handling strategy

  ## Returns
  - `:continue` - Processing should continue
  - `:stop` - Processing should stop
  """
  @spec should_continue_batch?(batch_results(), batch_opts()) :: :continue | :stop
  def should_continue_batch?(results, opts) when is_map(results) do
    error_handling = Keyword.get(opts, :error_handling, :continue)

    case error_handling do
      :fail_fast -> check_fail_fast_condition(results)
      :continue -> :continue
    end
  end

  # Private helper to check fail-fast condition
  @spec check_fail_fast_condition(batch_results()) :: :continue | :stop
  defp check_fail_fast_condition(results) do
    has_errors? = Enum.any?(results, fn {_id, result} -> match?({:error, _}, result) end)

    if has_errors?, do: :stop, else: :continue
  end

  @doc """
  Filters batch results based on success/failure status.

  ## Parameters
  - `results` - Batch results map
  - `filter` - `:successful`, `:failed`, or `:all`

  ## Returns
  Filtered results map
  """
  @spec filter_batch_results(batch_results(), :successful | :failed | :all) :: batch_results()
  def filter_batch_results(results, :successful) do
    results
    |> Enum.filter(fn {_id, result} -> match?({:ok, _}, result) end)
    |> Map.new()
  end

  def filter_batch_results(results, :failed) do
    results
    |> Enum.filter(fn {_id, result} -> match?({:error, _}, result) end)
    |> Map.new()
  end

  def filter_batch_results(results, :all), do: results

  # Private helper functions

  @spec process_task_results(Enumerable.t()) :: batch_results()
  defp process_task_results(task_stream) do
    task_stream
    |> Enum.map(&handle_task_result/1)
    |> Enum.reject(fn {system_id, _result} -> system_id == :unknown_system end)
    |> Map.new()
  end

  @spec handle_task_result(term()) :: {system_id() | :unknown_system, batch_result()}
  defp handle_task_result({:ok, {system_id, result}}) do
    {system_id, result}
  end

  defp handle_task_result({:exit, {system_id, reason}}) when is_integer(system_id) do
    Logger.error("Task exit for system", system_id: system_id, reason: inspect(reason))
    {system_id, {:error, {:task_exit, reason}}}
  end

  defp handle_task_result({:exit, reason}) do
    Logger.error("Unexpected task exit without system ID", reason: inspect(reason))
    {:unknown_system, {:error, {:unexpected_exit, reason}}}
  end

  defp handle_task_result(other) do
    Logger.error("Unexpected task result", result: inspect(other))
    {:unknown_system, {:error, {:unexpected_result, other}}}
  end

  @spec summarize_errors([{system_id(), {:error, term()}}]) :: map()
  defp summarize_errors(failed_results) do
    failed_results
    |> Enum.map(fn {_system_id, {:error, reason}} -> reason end)
    |> Enum.group_by(& &1)
    |> Enum.map(fn {error, occurrences} -> {error, length(occurrences)} end)
    |> Map.new()
  end

  @spec log_batch_completion([system_id()], batch_results(), integer()) :: :ok
  defp log_batch_completion(system_ids, results, duration) do
    stats = aggregate_batch_results(results)

    Logger.info(
      "Batch processing completed",
      [
        total_systems: length(system_ids),
        successful: stats.successful_systems,
        failed: stats.failed_systems,
        success_rate: stats.success_rate,
        duration_ms: duration
      ] ++
        if stats.failed_systems > 0 do
          [error_summary: stats.error_summary]
        else
          []
        end
    )
  end
end
