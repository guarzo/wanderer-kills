defmodule WandererKills.Infrastructure.BatchProcessor do
  @moduledoc """
  Unified batch processing module for handling parallel operations.

  This module provides consistent patterns for:
  - Parallel task execution with configurable concurrency
  - Result aggregation and reporting
  - Timeout and retry management

  ## Configuration

  Batch processing uses the concurrency configuration:

  ```elixir
  config :wanderer_kills,
    batch: %{
      concurrency_default: 10,
      batch_size: 50
    },
    timeouts: %{
      default_request_ms: 30_000
    }
  ```

  ## Usage

  ```elixir
  # Parallel processing (recommended)
  items = [1, 2, 3, 4, 5]
  {:ok, results} = BatchProcessor.process_parallel(items, &fetch_data/1)

  # With custom options
  {:ok, results} = BatchProcessor.process_parallel(items, &fetch_data/1,
    max_concurrency: 5,
    timeout: 60_000,
    description: "Fetching ship data"
  )

  # Sequential processing (use regular Enum.map for simple cases)
  results = Enum.map(items, &fetch_data/1)
  ```
  """

  require Logger
  alias WandererKills.Infrastructure.Config

  @type task_result :: {:ok, term()} | {:error, term()}
  @type batch_result :: {:ok, [term()]} | {:partial, [term()], [term()]} | {:error, term()}
  @type batch_opts :: [
          max_concurrency: pos_integer(),
          timeout: pos_integer(),
          description: String.t(),
          supervisor: GenServer.name()
        ]

  @doc """
  Processes items in parallel using Task.Supervisor with configurable concurrency.

  This is the main batch processing function that handles all parallel operations.
  For simple sequential processing, use `Enum.map/2` directly.

  ## Options
  - `:max_concurrency` - Maximum concurrent tasks (default: from config)
  - `:timeout` - Timeout per task in milliseconds (default: from config)
  - `:supervisor` - Task supervisor to use (default: WandererKills.TaskSupervisor)
  - `:description` - Description for logging (default: "items")

  ## Returns
  - `{:ok, results}` - If all items processed successfully
  - `{:partial, results, failures}` - If some items failed
  - `{:error, reason}` - If processing failed entirely
  """
  @spec process_parallel([term()], (term() -> task_result()), batch_opts()) :: batch_result()
  def process_parallel(items, process_fn, opts \\ []) when is_list(items) do
    max_concurrency = Keyword.get(opts, :max_concurrency, Config.batch().concurrency_default)
    timeout = Keyword.get(opts, :timeout, Config.timeouts().default_request_ms)
    supervisor = Keyword.get(opts, :supervisor, WandererKills.TaskSupervisor)
    description = Keyword.get(opts, :description, "items")

    Logger.info(
      "Processing #{length(items)} #{description} in parallel " <>
        "(max_concurrency: #{max_concurrency}, timeout: #{timeout}ms)"
    )

    start_time = System.monotonic_time()

    results =
      Task.Supervisor.async_stream_nolink(
        supervisor,
        items,
        process_fn,
        max_concurrency: max_concurrency,
        timeout: timeout
      )
      |> Enum.to_list()

    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    process_batch_results(results, length(items), description, duration_ms)
  end

  @doc """
  Executes a list of async tasks with timeout and error aggregation.

  ## Options
  - `:timeout` - Timeout for all tasks in milliseconds (default: from config)
  - `:description` - Description for logging (default: "tasks")

  ## Returns
  - `{:ok, results}` - If all tasks succeed
  - `{:partial, results, failures}` - If some tasks failed
  - `{:error, reason}` - If tasks failed entirely
  """
  @spec await_tasks([Task.t()], batch_opts()) :: batch_result()
  def await_tasks(tasks, opts \\ []) when is_list(tasks) do
    timeout = Keyword.get(opts, :timeout, Config.timeouts().default_request_ms)
    description = Keyword.get(opts, :description, "tasks")

    Logger.info("Awaiting #{length(tasks)} #{description} (timeout: #{timeout}ms)")

    start_time = System.monotonic_time()

    try do
      results = Task.await_many(tasks, timeout)

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      Logger.info("Completed #{length(tasks)} #{description} in #{duration_ms}ms")
      {:ok, results}
    rescue
      error ->
        duration = System.monotonic_time() - start_time
        duration_ms = System.convert_time_unit(duration, :native, :millisecond)

        Logger.error("Task await failed after #{duration_ms}ms",
          tasks: length(tasks),
          description: description,
          error: inspect(error)
        )

        {:error, error}
    end
  end

  # Private Functions

  @spec process_batch_results([term()], integer(), String.t(), integer()) :: batch_result()
  defp process_batch_results(results, total_count, description, duration_ms) do
    {successes, failures} = categorize_results(results)

    success_count = length(successes)
    failure_count = length(failures)

    case {success_count, failure_count} do
      {^total_count, 0} ->
        Logger.info("Successfully processed #{success_count} #{description} in #{duration_ms}ms")
        {:ok, successes}

      {0, ^total_count} ->
        Logger.error("Failed to process all #{total_count} #{description} in #{duration_ms}ms")
        {:error, "All items failed to process"}

      {_, _} ->
        Logger.warning(
          "Partially processed #{description} in #{duration_ms}ms: " <>
            "#{success_count} succeeded, #{failure_count} failed"
        )

        {:partial, successes, failures}
    end
  end

  @spec categorize_results([term()]) :: {[term()], [term()]}
  defp categorize_results(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, result}, {successes, failures} ->
        {[result | successes], failures}

      {:exit, reason}, {successes, failures} ->
        {successes, [{:exit, reason} | failures]}

      {:error, reason}, {successes, failures} ->
        {successes, [{:error, reason} | failures]}

      other, {successes, failures} ->
        Logger.warning("Unexpected async_stream result format: #{inspect(other)}")
        {successes, [{:unexpected, other} | failures]}
    end)
  end
end
