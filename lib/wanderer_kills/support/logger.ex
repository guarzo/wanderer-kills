defmodule WandererKills.Support.Logger do
  @moduledoc """
  Structured logging support with consistent metadata.
  
  This module provides a centralized logging interface that ensures all log
  messages include consistent metadata such as module, function, operation,
  and contextual information. It wraps Elixir's Logger with structured
  formatting and automatic metadata enrichment.
  
  ## Features
  
  - Automatic module and function detection
  - Consistent metadata structure
  - Operation context tracking
  - Performance timing helpers
  - Error standardization
  - Request ID propagation
  
  ## Usage
  
  ```elixir
  import WandererKills.Support.Logger
  
  # Basic logging with automatic metadata
  log_info("Processing killmail", killmail_id: 123456)
  
  # With operation context
  log_operation(:process_killmail, fn ->
    # ... processing logic ...
    {:ok, result}
  end, killmail_id: 123456)
  
  # Error logging with context
  log_error("Failed to fetch ESI data", error: reason, entity_id: 123)
  
  # Debug logging with timing
  log_timed_debug("ESI request", fn ->
    # ... make request ...
  end, service: :esi, endpoint: "/killmails/123")
  ```
  """
  
  require Logger
  
  @type log_level :: :debug | :info | :warning | :error
  @type metadata :: keyword()
  
  # ============================================================================
  # Public API
  # ============================================================================
  
  @doc """
  Logs a debug message with structured metadata.
  """
  @spec log_debug(String.t(), metadata()) :: :ok
  defmacro log_debug(message, metadata \\ []) do
    quote do
      unquote(__MODULE__).do_log(:debug, unquote(message), unquote(metadata), __ENV__)
    end
  end
  
  @doc """
  Logs an info message with structured metadata.
  """
  @spec log_info(String.t(), metadata()) :: :ok
  defmacro log_info(message, metadata \\ []) do
    quote do
      unquote(__MODULE__).do_log(:info, unquote(message), unquote(metadata), __ENV__)
    end
  end
  
  @doc """
  Logs a warning message with structured metadata.
  """
  @spec log_warning(String.t(), metadata()) :: :ok
  defmacro log_warning(message, metadata \\ []) do
    quote do
      unquote(__MODULE__).do_log(:warning, unquote(message), unquote(metadata), __ENV__)
    end
  end
  
  @doc """
  Logs an error message with structured metadata.
  """
  @spec log_error(String.t(), metadata()) :: :ok
  defmacro log_error(message, metadata \\ []) do
    quote do
      unquote(__MODULE__).do_log(:error, unquote(message), unquote(metadata), __ENV__)
    end
  end
  
  @doc """
  Logs the execution of an operation with timing and result.
  
  ## Parameters
  - `operation` - Name of the operation
  - `fun` - Function to execute
  - `metadata` - Additional metadata
  
  ## Returns
  - The result of the function execution
  
  ## Examples
  
  ```elixir
  log_operation(:fetch_killmail, fn ->
    ESI.get_killmail(id)
  end, killmail_id: id)
  ```
  """
  defmacro log_operation(operation, fun, metadata \\ []) do
    quote do
      operation = unquote(operation)
      metadata = unquote(metadata)
      env = __ENV__
      
      start_time = System.monotonic_time()
      
      # Log operation start
      unquote(__MODULE__).do_log(
        :debug,
        "Starting operation",
        Keyword.merge(metadata, [operation: operation, phase: :start]),
        env
      )
      
      # Execute operation
      result = try do
        unquote(fun).()
      rescue
        error ->
          duration_ms = System.convert_time_unit(
            System.monotonic_time() - start_time,
            :native,
            :millisecond
          )
          
          unquote(__MODULE__).do_log(
            :error,
            "Operation failed with exception",
            Keyword.merge(metadata, [
              operation: operation,
              phase: :error,
              error: inspect(error),
              duration_ms: duration_ms
            ]),
            env
          )
          
          reraise error, __STACKTRACE__
      end
      
      # Calculate duration
      duration_ms = System.convert_time_unit(
        System.monotonic_time() - start_time,
        :native,
        :millisecond
      )
      
      # Log result
      {level, phase} = case result do
        {:ok, _} -> {:debug, :success}
        {:error, _} -> {:warning, :failure}
        _ -> {:debug, :complete}
      end
      
      unquote(__MODULE__).do_log(
        level,
        "Operation #{phase}",
        Keyword.merge(metadata, [
          operation: operation,
          phase: phase,
          duration_ms: duration_ms
        ]),
        env
      )
      
      result
    end
  end
  
  @doc """
  Logs a debug operation with timing information.
  
  Useful for operations that should only be logged in debug mode.
  """
  defmacro log_timed_debug(description, fun, metadata \\ []) do
    quote do
      if Logger.level() == :debug do
        description = unquote(description)
        metadata = unquote(metadata)
        env = __ENV__
        
        start_time = System.monotonic_time()
        result = unquote(fun).()
        
        duration_ms = System.convert_time_unit(
          System.monotonic_time() - start_time,
          :native,
          :millisecond
        )
        
        unquote(__MODULE__).do_log(
          :debug,
          description,
          Keyword.merge(metadata, [duration_ms: duration_ms]),
          env
        )
        
        result
      else
        unquote(fun).()
      end
    end
  end
  
  @doc """
  Sets metadata for the current process.
  
  This metadata will be included in all subsequent log messages
  from this process.
  
  ## Examples
  
  ```elixir
  set_metadata(request_id: "abc123", user_id: 456)
  ```
  """
  @spec set_metadata(metadata()) :: :ok
  def set_metadata(metadata) when is_list(metadata) do
    Logger.metadata(metadata)
  end
  
  @doc """
  Updates metadata for the current process.
  
  Merges new metadata with existing metadata.
  """
  @spec update_metadata(metadata()) :: :ok
  def update_metadata(metadata) when is_list(metadata) do
    current = Logger.metadata()
    Logger.metadata(Keyword.merge(current, metadata))
  end
  
  @doc """
  Clears metadata for the current process.
  """
  @spec clear_metadata() :: :ok
  def clear_metadata do
    Logger.reset_metadata()
  end
  
  @doc """
  Gets current process metadata.
  """
  @spec get_metadata() :: metadata()
  def get_metadata do
    Logger.metadata()
  end
  
  # ============================================================================
  # Implementation Functions (not macros, so they can be called from macros)
  # ============================================================================
  
  @doc false
  def do_log(level, message, metadata, env) do
    # Build structured metadata
    structured_metadata = build_metadata(metadata, env)
    
    # Format message with context
    formatted_message = format_message(message, structured_metadata)
    
    # Log with appropriate level
    case level do
      :debug -> Logger.debug(formatted_message, structured_metadata)
      :info -> Logger.info(formatted_message, structured_metadata)
      :warning -> Logger.warning(formatted_message, structured_metadata)
      :error -> Logger.error(formatted_message, structured_metadata)
    end
    
    :ok
  end
  
  # ============================================================================
  # Private Functions
  # ============================================================================
  
  defp build_metadata(metadata, env) do
    base_metadata = [
      module: env.module,
      function: env.function,
      line: env.line
    ]
    
    # Add timestamp if not present
    metadata_with_time = 
      if Keyword.has_key?(metadata, :timestamp) do
        metadata
      else
        [{:timestamp, DateTime.utc_now() |> DateTime.to_iso8601()} | metadata]
      end
    
    # Merge with any process metadata
    process_metadata = Logger.metadata()
    
    base_metadata
    |> Keyword.merge(process_metadata)
    |> Keyword.merge(metadata_with_time)
    |> normalize_metadata()
  end
  
  defp format_message(message, metadata) do
    # Extract key context fields for the message prefix
    context_parts = []
    
    # Add module context if available
    context_parts = if module = Keyword.get(metadata, :module) do
      module_name = module |> Module.split() |> List.last()
      ["[#{module_name}]" | context_parts]
    else
      context_parts
    end
    
    # Add operation if available
    context_parts = if operation = Keyword.get(metadata, :operation) do
      context_parts ++ ["#{operation}:"]
    else
      context_parts
    end
    
    # Build final message
    case context_parts do
      [] -> message
      parts -> Enum.join(parts, " ") <> " " <> message
    end
  end
  
  defp normalize_metadata(metadata) do
    metadata
    |> Enum.map(fn
      # Ensure errors are properly stringified
      {:error, error} when is_exception(error) ->
        {:error, Exception.message(error)}
        
      {:error, error} when is_atom(error) ->
        {:error, error}
        
      {:error, error} ->
        {:error, inspect(error)}
        
      # Ensure IDs are integers when possible
      {key, value} when key in [:killmail_id, :system_id, :character_id, :corporation_id, :alliance_id] ->
        {key, normalize_id(value)}
        
      # Pass through other metadata
      other ->
        other
    end)
  end
  
  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> id
    end
  end
  defp normalize_id(id), do: id
  
  # ============================================================================
  # Convenience Functions
  # ============================================================================
  
  @doc """
  Logs entry into a function with parameters.
  
  ## Examples
  
  ```elixir
  def process_killmail(id, options) do
    log_function_entry(id: id, options: options)
    # ... function body ...
  end
  ```
  """
  defmacro log_function_entry(params \\ []) do
    quote do
      {function, arity} = __ENV__.function
      unquote(__MODULE__).do_log(
        :debug,
        "Entering #{function}/#{arity}",
        Keyword.merge(unquote(params), [phase: :entry]),
        __ENV__
      )
    end
  end
  
  @doc """
  Logs exit from a function with result.
  """
  defmacro log_function_exit(result, metadata \\ []) do
    quote do
      {function, arity} = __ENV__.function
      result = unquote(result)
      
      {level, status} = case result do
        {:ok, _} -> {:debug, :success}
        {:error, _} -> {:debug, :error}
        _ -> {:debug, :complete}
      end
      
      unquote(__MODULE__).do_log(
        level,
        "Exiting #{function}/#{arity}",
        Keyword.merge(unquote(metadata), [phase: :exit, status: status]),
        __ENV__
      )
      
      result
    end
  end
end