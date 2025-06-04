defmodule WandererKills.Core.Shared.Concurrency do
  @moduledoc """
  Shared concurrency helpers for processing operations across the application.

  This module provides backward compatibility wrappers around the new
  `WandererKills.Core.BatchProcessor` module. New code should use
  `BatchProcessor` directly for better consistency and features.

  ## Deprecation Notice

  This module is maintained for backward compatibility. New code should use:
  - `WandererKills.Core.BatchProcessor.process_parallel/3`
  - `WandererKills.Core.BatchProcessor.process_sequential/3`
  - `WandererKills.Core.BatchProcessor.await_tasks/2`
  """

  require Logger
  alias WandererKills.Core.BatchProcessor

  @type task_result :: BatchProcessor.task_result()
  @type batch_opts :: BatchProcessor.batch_opts()

  @doc """
  Executes a list of items in parallel using Task.async and aggregates results.

  ## Deprecation Notice
  Use `WandererKills.Core.BatchProcessor.await_tasks/2` instead.

  ## Parameters
  - `items` - List of items to process
  - `task_fn` - Function that takes an item and returns a task
  - `timeout` - Timeout for each task in milliseconds

  ## Returns
  - `:ok` - If all tasks succeed
  - `{:error, reason}` - If any task fails
  """
  @spec execute_parallel_tasks([term()], (term() -> Task.t()), pos_integer()) ::
          :ok | {:error, term()}
  def execute_parallel_tasks(items, task_fn, timeout) when is_list(items) do
    tasks = Enum.map(items, task_fn)

    case BatchProcessor.await_tasks(tasks, timeout: timeout, description: "parallel tasks") do
      {:ok, _results} -> :ok
      {:partial, _results, _failures} -> {:error, :partial_failure}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Executes a batch operation using Task.Supervisor.async_stream_nolink with error aggregation.

  ## Deprecation Notice
  Use `WandererKills.Core.BatchProcessor.process_parallel/3` instead.

  ## Parameters
  - `supervisor` - Task supervisor name/pid
  - `items` - List of items to process
  - `process_fn` - Function to process each item
  - `opts` - Options including:
    - `:max_concurrency` - Maximum concurrent tasks
    - `:timeout` - Timeout per task in milliseconds

  ## Returns
  - `:ok` - If all items processed successfully
  - `{:error, reason}` - If processing failed
  """
  @spec execute_batch_operation(
          GenServer.name(),
          [term()],
          (term() -> task_result()),
          batch_opts()
        ) ::
          :ok | {:error, term()}
  def execute_batch_operation(supervisor, items, process_fn, opts) when is_list(items) do
    batch_opts = Keyword.merge(opts, supervisor: supervisor, description: "batch operation")

    case BatchProcessor.process_parallel(items, process_fn, batch_opts) do
      {:ok, _results} -> :ok
      {:partial, _results, _failures} -> {:error, :batch_processing_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Aggregates batch operation results and returns success/failure status.

  ## Deprecation Notice
  This function is now handled internally by BatchProcessor.

  ## Parameters
  - `results` - List of task results
  - `total_count` - Total number of items processed

  ## Returns
  - `:ok` - If all succeeded
  - `{:error, :batch_processing_failed}` - If any failed
  """
  @spec aggregate_batch_results([{:ok, task_result()} | {:exit, term()}], pos_integer()) ::
          :ok | {:error, term()}
  def aggregate_batch_results(results, total_count) do
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, :ok} -> true
        _ -> false
      end)

    if Enum.empty?(failures) do
      Logger.info("Successfully processed #{length(successes)}/#{total_count} items")
      :ok
    else
      Logger.error("Failed to process #{length(failures)}/#{total_count} items")
      {:error, :batch_processing_failed}
    end
  end

  @doc """
  Executes a function with backoff and error handling for each item in a list.

  ## Deprecation Notice
  Use `WandererKills.Core.BatchProcessor.process_sequential/3` instead.

  ## Parameters
  - `items` - List of items to process
  - `process_fn` - Function to process each item
  - `description` - Description for logging

  ## Returns
  - `:ok` - If all items processed successfully
  - `{:error, reason}` - If processing failed
  """
  @spec process_items_sequentially([term()], (term() -> task_result()), String.t()) ::
          :ok | {:error, term()}
  def process_items_sequentially(items, process_fn, description) when is_list(items) do
    case BatchProcessor.process_sequential(items, process_fn, description: description) do
      {:ok, _results} -> :ok
      {:partial, _results, _failures} -> {:error, :partial_failure}
      {:error, reason} -> {:error, reason}
    end
  end
end
