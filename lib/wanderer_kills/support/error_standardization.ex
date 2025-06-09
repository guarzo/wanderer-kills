defmodule WandererKills.Support.ErrorStandardization do
  @moduledoc """
  Module to help standardize error returns across the codebase.
  
  This module provides helpers and guidelines for converting
  legacy error patterns to the standardized Error struct approach.
  
  ## Error Return Standards
  
  1. All functions should return `{:ok, result}` or `{:error, %Error{}}`
  2. Avoid returning bare atoms or nil on error
  3. Use domain-specific error constructors from WandererKills.Support.Error
  4. Include meaningful error messages and context
  
  ## Conversion Examples
  
  ```elixir
  # Old pattern
  {:error, :not_found}
  
  # New pattern
  {:error, Error.not_found_error("Resource not found", %{resource_id: id})}
  
  # Old pattern
  nil  # on error
  
  # New pattern
  {:error, Error.system_error(:operation_failed, "Operation failed")}
  ```
  """
  
  alias WandererKills.Support.Error
  
  @doc """
  Converts common atom errors to standardized Error structs.
  
  This function helps migrate legacy error returns to the new standard.
  """
  @spec standardize_error(atom() | {atom(), term()} | term()) :: Error.t()
  def standardize_error(:not_found), do: Error.not_found_error()
  def standardize_error(:timeout), do: Error.timeout_error()
  def standardize_error(:invalid_format), do: Error.invalid_format_error()
  def standardize_error(:rate_limited), do: Error.rate_limit_error()
  def standardize_error(:connection_failed), do: Error.connection_error()
  
  def standardize_error({:not_found, details}) when is_binary(details) do
    Error.not_found_error(details)
  end
  
  def standardize_error({:timeout, details}) when is_binary(details) do
    Error.timeout_error(details)
  end
  
  def standardize_error({:invalid_format, details}) when is_binary(details) do
    Error.invalid_format_error(details)
  end
  
  def standardize_error(other) do
    Error.system_error(:unknown_error, "Unknown error: #{inspect(other)}")
  end
  
  @doc """
  Wraps a function result to ensure it returns standardized errors.
  
  ## Examples
  
  ```elixir
  # Wrap a function that might return nil
  with_standard_error(fn -> some_function() end, :cache, :miss, "Cache miss")
  
  # Wrap a function that returns {:error, atom}
  with_standard_error(fn -> legacy_function() end, :http, :request_failed)
  ```
  """
  @spec with_standard_error(
          (-> {:ok, term()} | {:error, term()} | term()),
          Error.domain(),
          Error.error_type(),
          String.t() | nil
        ) :: {:ok, term()} | {:error, Error.t()}
  def with_standard_error(fun, domain, type, message \\ nil) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}
        
      {:error, %Error{} = error} ->
        {:error, error}
        
      {:error, reason} ->
        msg = message || "Operation failed: #{inspect(reason)}"
        {:error, create_error(domain, type, msg)}
        
      nil ->
        msg = message || "Operation returned nil"
        {:error, create_error(domain, type, msg)}
        
      result ->
        # Assume non-tuple results are successful
        {:ok, result}
    end
  end
  
  @doc """
  Ensures a function returns {:ok, result} or {:error, %Error{}}.
  
  Useful for wrapping functions that return bare values or nil.
  """
  @spec ensure_error_tuple(term(), Error.domain(), Error.error_type()) :: 
          {:ok, term()} | {:error, Error.t()}
  def ensure_error_tuple(nil, domain, type) do
    {:error, create_error(domain, type, "Operation returned nil")}
  end
  
  def ensure_error_tuple({:ok, _} = result, _domain, _type), do: result
  def ensure_error_tuple({:error, %Error{}} = result, _domain, _type), do: result
  
  def ensure_error_tuple({:error, reason}, domain, type) do
    {:error, create_error(domain, type, "Operation failed: #{inspect(reason)}")}
  end
  
  def ensure_error_tuple(result, _domain, _type) do
    {:ok, result}
  end
  
  # Private helper to create errors based on domain
  defp create_error(:http, type, message), do: Error.http_error(type, message)
  defp create_error(:cache, type, message), do: Error.cache_error(type, message)
  defp create_error(:killmail, type, message), do: Error.killmail_error(type, message)
  defp create_error(:system, type, message), do: Error.system_error(type, message)
  defp create_error(:esi, type, message), do: Error.esi_error(type, message)
  defp create_error(:zkb, type, message), do: Error.zkb_error(type, message)
  defp create_error(domain, type, message) do
    Error.system_error(type, "[#{domain}] #{message}")
  end
end