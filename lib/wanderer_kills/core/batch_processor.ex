defmodule WandererKills.Core.BatchProcessor do
  @moduledoc """
  Unified batch processing module for handling parallel and sequential operations.

  This module provides consistent patterns for:
  - Parallel task execution with configurable concurrency
  - Sequential processing with error handling
  - Result aggregation and reporting
  - Timeout and retry management

  All batch operations use the same configuration and error handling patterns,
  making it easier to reason about concurrency across the application.

  ## Configuration

  Batch processing uses the concurrency configuration:

  ```elixir
  config :wanderer_kills,
    concurrency: %{
      max_concurrent: 10,
      batch_size: 50,
      timeout_ms: 30_000
    }
  ```

  ## Usage

  ```elixir
  # Parallel processing
  items = [1, 2, 3, 4, 5]
  {:ok, results} = BatchProcessor.process_parallel(items, &fetch_data/1)

  # Sequential processing
  {:ok, results} = BatchProcessor.process_sequential(items, &fetch_data/1)

  # Custom batch with options
  {:ok, results} = BatchProcessor.process_parallel(items, &fetch_data/1,
    max_concurrency: 5,
    timeout: 60_000,
    description: "Fetching ship data"
  )
  ```
  """

  require Logger
  alias WandererKills.Constants

  @type task_result :: {:ok, term()} | {:error, term()}
  @type batch_result :: {:ok, [term()]} | {:partial, [term()], [term()]} | {:error, term()}
  @type batch_opts :: [
          max_concurrency: pos_integer(),
          timeout: pos_integer(),
          batch_size: pos_integer(),
          description: String.t(),
          supervisor: GenServer.name()
        ]

  @doc """
  Processes items in parallel using Task.Supervisor with configurable concurrency.

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
    max_concurrency = Keyword.get(opts, :max_concurrency, Constants.concurrency(:default))
    timeout = Keyword.get(opts, :timeout, Constants.timeout(:http))
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
  Processes items sequentially with error handling.

  ## Options
  - `:timeout` - Timeout per task in milliseconds (default: from config)
  - `:description` - Description for logging (default: "items")

  ## Returns
  - `{:ok, results}` - If all items processed successfully
  - `{:partial, results, failures}` - If some items failed
  - `{:error, reason}` - If processing failed entirely
  """
  @spec process_sequential([term()], (term() -> task_result()), batch_opts()) :: batch_result()
  def process_sequential(items, process_fn, opts \\ []) when is_list(items) do
    description = Keyword.get(opts, :description, "items")

    Logger.info("Processing #{length(items)} #{description} sequentially")

    start_time = System.monotonic_time()

    results = Enum.map(items, process_fn)

    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    # Convert to the same format as async_stream results
    stream_results = Enum.map(results, fn result -> {:ok, result} end)

    process_batch_results(stream_results, length(items), description, duration_ms)
  end

  @doc """
  Processes items in batches with configurable batch size.

  ## Options
  - `:batch_size` - Number of items per batch (default: from config)
  - `:max_concurrency` - Maximum concurrent batches (default: from config)
  - `:timeout` - Timeout per batch in milliseconds (default: from config)
  - `:description` - Description for logging (default: "items")

  ## Returns
  - `{:ok, results}` - If all batches processed successfully
  - `{:partial, results, failures}` - If some batches failed
  - `{:error, reason}` - If processing failed entirely
  """
  @spec process_batched([term()], (term() -> task_result()), batch_opts()) :: batch_result()
  def process_batched(items, process_fn, opts \\ []) when is_list(items) do
    batch_size = Keyword.get(opts, :batch_size, Constants.concurrency(:batch_size))
    description = Keyword.get(opts, :description, "items")

    Logger.info("Processing #{length(items)} #{description} in batches of #{batch_size}")

    batches = Enum.chunk_every(items, batch_size)

    batch_process_fn = fn batch ->
      case process_sequential(batch, process_fn, opts) do
        {:ok, results} -> {:ok, results}
        {:partial, results, _failures} -> {:ok, results}
        {:error, reason} -> {:error, reason}
      end
    end

    process_parallel(
      batches,
      batch_process_fn,
      Keyword.merge(opts, description: "batches of #{description}")
    )
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
    timeout = Keyword.get(opts, :timeout, Constants.timeout(:http))
    description = Keyword.get(opts, :description, "tasks")

    Logger.info("Awaiting #{length(tasks)} #{description} (timeout: #{timeout}ms)")

    start_time = System.monotonic_time()

    try do
      results = Task.await_many(tasks, timeout)

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Convert to the same format as async_stream results
      stream_results = Enum.map(results, fn result -> {:ok, result} end)

      process_batch_results(stream_results, length(tasks), description, duration_ms)
    rescue
      error ->
        Logger.error("Task execution failed: #{inspect(error)}")
        {:error, :task_execution_failed}
    end
  end

  # Private helper functions

  @spec process_batch_results(
          [{:ok, task_result()} | {:exit, term()}],
          pos_integer(),
          String.t(),
          pos_integer()
        ) :: batch_result()
  defp process_batch_results(results, total_count, description, duration_ms) do
    {successes, failures} = partition_results(results)

    success_count = length(successes)
    failure_count = length(failures)

    Logger.info(
      "Completed processing #{description}: " <>
        "#{success_count}/#{total_count} succeeded, " <>
        "#{failure_count}/#{total_count} failed " <>
        "(#{duration_ms}ms)"
    )

    case {successes, failures} do
      {results, []} when length(results) == total_count ->
        success_values = Enum.map(results, fn {:ok, value} -> value end)
        {:ok, success_values}

      {[], _failures} ->
        Logger.error("All #{description} failed")
        {:error, :all_failed}

      {partial_results, failures} ->
        Logger.warning("Partial success for #{description}: #{success_count}/#{total_count}")
        success_values = Enum.map(partial_results, fn {:ok, value} -> value end)
        failure_reasons = Enum.map(failures, fn {:error, reason} -> reason end)
        {:partial, success_values, failure_reasons}
    end
  end

  @spec partition_results([{:ok, task_result()} | {:exit, term()}]) ::
          {[{:ok, term()}], [{:error, term()}]}
  defp partition_results(results) do
    Enum.split_with(results, fn
      {:ok, {:ok, _value}} -> true
      {:ok, :ok} -> true
      _ -> false
    end)
    |> then(fn {successes, failures} ->
      formatted_successes =
        Enum.map(successes, fn
          {:ok, {:ok, value}} -> {:ok, value}
          {:ok, :ok} -> {:ok, :ok}
        end)

      formatted_failures =
        Enum.map(failures, fn
          {:ok, {:error, reason}} -> {:error, reason}
          {:exit, reason} -> {:error, {:exit, reason}}
        end)

      {formatted_successes, formatted_failures}
    end)
  end
end
