defmodule WandererKills.Result do
  @moduledoc """
  Shared result handling utilities for WandererKills.

  This module provides standardized functions for working with result tuples
  and other common patterns used throughout the application. It helps reduce
  boilerplate code and ensures consistent error handling.

  ## Usage

  ```elixir
  # Convert :ok to {:ok, true}
  result |> Result.ok_to_bool()

  # Unwrap result with default
  value = Result.unwrap_or(result, default_value)

  # Map over success values
  Result.map_ok(result, &transform_function/1)

  # Tap for side effects
  Result.tap_ok(result, &Logger.info/1)
  ```
  """

  @type result(success) :: {:ok, success} | {:error, term()}
  @type simple_result :: :ok | {:error, term()}

  @doc """
  Converts `:ok` to `{:ok, true}` and passes errors through unchanged.

  This is useful for functions that return `:ok` but you need a boolean
  value to indicate success.

  ## Examples

  ```elixir
  :ok |> Result.ok_to_bool()
  # {:ok, true}

  {:error, reason} |> Result.ok_to_bool()
  # {:error, reason}
  ```
  """
  @spec ok_to_bool(simple_result()) :: result(boolean())
  def ok_to_bool(:ok), do: {:ok, true}
  def ok_to_bool({:error, _} = error), do: error

  @doc """
  Converts `{:ok, _}` to `{:ok, true}` and passes errors through unchanged.

  This is useful for functions that return `{:ok, value}` but you only
  care about success/failure.

  ## Examples

  ```elixir
  {:ok, "some value"} |> Result.success_to_bool()
  # {:ok, true}

  {:error, reason} |> Result.success_to_bool()
  # {:error, reason}
  ```
  """
  @spec success_to_bool(result(term())) :: result(boolean())
  def success_to_bool({:ok, _}), do: {:ok, true}
  def success_to_bool({:error, _} = error), do: error

  @doc """
  Unwraps a result tuple, returning the success value or a default.

  ## Examples

  ```elixir
  {:ok, "value"} |> Result.unwrap_or("default")
  # "value"

  {:error, reason} |> Result.unwrap_or("default")
  # "default"
  ```
  """
  @spec unwrap_or(result(success), success) :: success when success: term()
  def unwrap_or({:ok, value}, _default), do: value
  def unwrap_or({:error, _}, default), do: default

  @doc """
  Maps a function over the success value of a result.

  ## Examples

  ```elixir
  {:ok, 5} |> Result.map_ok(&(&1 * 2))
  # {:ok, 10}

  {:error, reason} |> Result.map_ok(&(&1 * 2))
  # {:error, reason}
  ```
  """
  @spec map_ok(result(a), (a -> b)) :: result(b) when a: term(), b: term()
  def map_ok({:ok, value}, fun), do: {:ok, fun.(value)}
  def map_ok({:error, _} = error, _fun), do: error

  @doc """
  Maps a function over the error value of a result.

  ## Examples

  ```elixir
  {:error, "error"} |> Result.map_error(&String.upcase/1)
  # {:error, "ERROR"}

  {:ok, value} |> Result.map_error(&String.upcase/1)
  # {:ok, value}
  ```
  """
  @spec map_error(result(success), (term() -> term())) :: result(success) when success: term()
  def map_error({:ok, _} = success, _fun), do: success
  def map_error({:error, error}, fun), do: {:error, fun.(error)}

  @doc """
  Executes a side effect function on success values without changing the result.

      ## Examples

  ```elixir
  result = {:ok, %{id: 123}}
  result |> Result.tap_ok(fn killmail -> Logger.info("Processed: {killmail.id}") end)
  # {:ok, %{id: 123}} (and logs the message)
  ```
  """
  @spec tap_ok(result(success), (success -> term())) :: result(success) when success: term()
  def tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  def tap_ok({:error, _} = error, _fun), do: error

  @doc """
  Executes a side effect function on error values without changing the result.

      ## Examples

  ```elixir
  result = {:error, "failed"}
  result |> Result.tap_error(fn reason -> Logger.error("Failed: {inspect(reason)}") end)
  # {:error, "failed"} (and logs the error)
  ```
  """
  @spec tap_error(result(success), (term() -> term())) :: result(success) when success: term()
  def tap_error({:ok, _} = success, _fun), do: success

  def tap_error({:error, error} = result, fun) do
    fun.(error)
    result
  end

  @doc """
  Returns true if the result is a success, false otherwise.

  ## Examples

  ```elixir
  {:ok, value} |> Result.ok?()
  # true

  {:error, reason} |> Result.ok?()
  # false
  ```
  """
  @spec ok?(result(term())) :: boolean()
  def ok?({:ok, _}), do: true
  def ok?({:error, _}), do: false

  @doc """
  Returns true if the result is an error, false otherwise.

  ## Examples

  ```elixir
  {:error, reason} |> Result.error?()
  # true

  {:ok, value} |> Result.error?()
  # false
  ```
  """
  @spec error?(result(term())) :: boolean()
  def error?({:error, _}), do: true
  def error?({:ok, _}), do: false

  @doc """
  Chains multiple result-returning functions together.

  Stops at the first error and returns it, otherwise returns the
  final success value.

  ## Examples

  ```elixir
  {:ok, 5}
  |> Result.and_then(&{:ok, &1 * 2})
  |> Result.and_then(&{:ok, &1 + 1})
  # {:ok, 11}

  {:ok, 5}
  |> Result.and_then(&{:ok, &1 * 2})
  |> Result.and_then(fn _ -> {:error, "failed"} end)
  # {:error, "failed"}
  ```
  """
  @spec and_then(result(a), (a -> result(b))) :: result(b) when a: term(), b: term()
  def and_then({:ok, value}, fun), do: fun.(value)
  def and_then({:error, _} = error, _fun), do: error

  @doc """
  Provides a fallback result if the first result is an error.

  ## Examples

  ```elixir
  {:error, "failed"} |> Result.or_else(fn _ -> {:ok, "fallback"} end)
  # {:ok, "fallback"}

  {:ok, "success"} |> Result.or_else(fn _ -> {:ok, "fallback"} end)
  # {:ok, "success"}
  ```
  """
  @spec or_else(result(success), (term() -> result(success))) :: result(success)
        when success: term()
  def or_else({:ok, _} = success, _fun), do: success
  def or_else({:error, error}, fun), do: fun.(error)

  @doc """
  Combines multiple results into a single result with a list of values.

  If all results are successful, returns `{:ok, [values]}`.
  If any result is an error, returns the first error.

  ## Examples

  ```elixir
  [
    {:ok, 1},
    {:ok, 2},
    {:ok, 3}
  ] |> Result.collect()
  # {:ok, [1, 2, 3]}

  [
    {:ok, 1},
    {:error, "failed"},
    {:ok, 3}
  ] |> Result.collect()
  # {:error, "failed"}
  ```
  """
  @spec collect([result(term())]) :: result([term()])
  def collect(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, _} = error, _acc -> {:halt, error}
    end)
    |> map_ok(&Enum.reverse/1)
  end
end
