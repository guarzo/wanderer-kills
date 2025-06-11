defmodule WandererKills.Support.SupervisedTask do
  @moduledoc """
  Wrapper for supervised async tasks with telemetry and error tracking.

  This module provides a consistent interface for starting supervised tasks
  with built-in telemetry events and error tracking.

  ## Usage

      SupervisedTask.start_child(fn ->
        # Your async work
      end, task_name: "webhook_notification")

  ## Telemetry Events

  - `[:wanderer_kills, :task, :start]` - When a task starts
  - `[:wanderer_kills, :task, :stop]` - When a task completes successfully
  - `[:wanderer_kills, :task, :error]` - When a task fails with an error
  """

  require Logger

  @doc """
  Starts a supervised task with telemetry tracking.

  ## Options
  - `:task_name` - Name for the task (used in telemetry)
  - `:metadata` - Additional metadata for telemetry events
  """
  @spec start_child(fun(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_child(fun, opts \\ []) do
    task_name = Keyword.get(opts, :task_name, "unnamed")
    metadata = Keyword.get(opts, :metadata, %{})
    
    wrapped_fun = fn ->
      start_time = System.monotonic_time()
      task_metadata = Map.merge(metadata, %{task_name: task_name})
      
      # Emit start event
      :telemetry.execute(
        [:wanderer_kills, :task, :start],
        %{system_time: System.system_time()},
        task_metadata
      )
      
      try do
        result = fun.()
        
        # Emit stop event on success
        duration = System.monotonic_time() - start_time
        :telemetry.execute(
          [:wanderer_kills, :task, :stop],
          %{duration: duration},
          task_metadata
        )
        
        result
      rescue
        error ->
          # Emit error event
          duration = System.monotonic_time() - start_time
          
          error_metadata = Map.merge(task_metadata, %{
            error: Exception.format(:error, error),
            error_type: error.__struct__
          })
          
          :telemetry.execute(
            [:wanderer_kills, :task, :error],
            %{duration: duration},
            error_metadata
          )
          
          Logger.error("Supervised task failed", error_metadata)
          
          # Re-raise to let supervisor handle
          reraise error, __STACKTRACE__
      end
    end
    
    Task.Supervisor.start_child(WandererKills.TaskSupervisor, wrapped_fun)
  end

  @doc """
  Starts a supervised task and awaits the result with a timeout.

  This is useful when you need the result of the async operation.
  """
  @spec async(fun(), keyword()) :: {:ok, term()} | {:error, term()}
  def async(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    case Task.Supervisor.async(WandererKills.TaskSupervisor, fun) do
      %Task{} = task ->
        try do
          {:ok, Task.await(task, timeout)}
        catch
          :exit, {:timeout, _} ->
            Task.Supervisor.terminate_child(WandererKills.TaskSupervisor, task.pid)
            {:error, :timeout}
        end
        
      error ->
        error
    end
  end
end