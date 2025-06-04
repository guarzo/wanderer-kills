defmodule WandererKills.Cache.ErrorHandler do
  @moduledoc """
  Utility functions for standardizing error handling and return conventions across cache modules.

  This module provides standardized result handling to ensure consistent
  return patterns across all cache operations and related modules.
  """

  @type cache_result :: {:ok, term()} | {:error, term()}
  @type cache_status :: :ok | {:error, term()}

  @doc """
  Standardizes cache operation results.

  Converts various return patterns into consistent {:ok, value} | {:error, reason} tuples.

  ## Parameters
  - `result` - The result to standardize

  ## Returns
  - `{:ok, value}` - On success
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  # Standardize raw values
  {:ok, "value"} = standardize_result("value")

  # Standardize nil
  {:ok, nil} = standardize_result(nil)

  # Pass through errors
  {:error, :not_found} = standardize_result({:error, :not_found})

  # Standardize status codes
  :ok = standardize_status(:ok)
  {:error, reason} = standardize_status({:error, reason})
  ```
  """
  @spec standardize_result(term()) :: cache_result()
  def standardize_result({:ok, value}), do: {:ok, value}
  def standardize_result({:error, reason}), do: {:error, reason}
  def standardize_result(value), do: {:ok, value}

  @doc """
  Standardizes cache status results.

  Ensures cache operations return either :ok or {:error, reason}.

  ## Parameters
  - `result` - The result to standardize

  ## Returns
  - `:ok` - On success
  - `{:error, reason}` - On failure
  """
  @spec standardize_status(term()) :: cache_status()
  def standardize_status(:ok), do: :ok
  def standardize_status({:ok, _}), do: :ok
  def standardize_status({:error, reason}), do: {:error, reason}
  def standardize_status(_), do: :ok

  @doc """
  Wraps a function call with standardized error handling and provides a default value on error.

  This function makes error semantics immediately clear to callers: it will either
  return the function result wrapped in {:ok, result} or return {:ok, default} on error.

  ## Parameters
  - `fun` - Function to call
  - `default` - Default value to return on error (optional)

  ## Returns
  - `{:ok, result}` - On success
  - `{:ok, default}` - On error (when default is provided)
  - `{:error, reason}` - On error (when no default is provided)

  ## Example

  ```elixir
  # With default value
  {:ok, "fallback"} = wrap_with_default(fn -> raise "error" end, "fallback")

  # Without default value
  {:error, %RuntimeError{}} = wrap_with_default(fn -> raise "error" end)
  ```
  """
  @spec wrap_with_default((-> term()), term()) :: cache_result()
  def wrap_with_default(fun, default \\ nil) when is_function(fun, 0) do
    try do
      result = fun.()
      standardize_result(result)
    rescue
      error ->
        if default == nil do
          {:error, error}
        else
          {:ok, default}
        end
    catch
      thrown_value ->
        case {thrown_value, default} do
          {{:error, reason}, nil} -> {:error, reason}
          {{:error, _reason}, default_val} -> {:ok, default_val}
          {_, nil} -> {:error, thrown_value}
          {_, default_val} -> {:ok, default_val}
        end
    end
  end

  @doc """
  Handles nil values consistently across cache operations.

  ## Parameters
  - `value` - The value to check
  - `default` - Default value to return if value is nil

  ## Returns
  - The original value if not nil
  - The default value if original is nil
  """
  @spec handle_nil(term(), term()) :: term()
  def handle_nil(nil, default), do: default
  def handle_nil(value, _default), do: value

  @doc """
  Ensures a cache result has a consistent error format.

  ## Parameters
  - `result` - The result to normalize

  ## Returns
  - Normalized result with consistent error format
  """
  @spec normalize_error(cache_result()) :: cache_result()
  def normalize_error({:ok, value}), do: {:ok, value}
  def normalize_error({:error, reason}) when is_binary(reason), do: {:error, reason}
  def normalize_error({:error, reason}) when is_atom(reason), do: {:error, reason}
  def normalize_error({:error, reason}), do: {:error, inspect(reason)}
end
