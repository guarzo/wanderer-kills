defmodule WandererKills.Observability.LogFormatter do
  @moduledoc """
  Consistent formatting for structured logging across the application.
  
  This module provides utilities for formatting log messages in a consistent,
  concise manner that's easy to parse and analyze.
  """
  
  @doc """
  Formats a statistics log message with key-value pairs.
  
  ## Examples
  
      iex> format_stats("WebSocket", %{connections: 10, kills_sent: 100})
      "[WebSocket] connections: 10 | kills_sent: 100"
  """
  @spec format_stats(String.t(), map()) :: String.t()
  def format_stats(component, stats) when is_map(stats) do
    pairs = 
      stats
      |> Enum.map(fn {k, v} -> "#{k}: #{format_value(v)}" end)
      |> Enum.join(" | ")
    
    "[#{component}] #{pairs}"
  end
  
  @doc """
  Formats an operation log message.
  
  ## Examples
  
      iex> format_operation("KillStore", "insert", %{count: 5, duration_ms: 123})
      "[KillStore] insert - count: 5 | duration_ms: 123"
  """
  @spec format_operation(String.t(), String.t(), map()) :: String.t()
  def format_operation(component, operation, details \\ %{}) do
    if map_size(details) > 0 do
      "[#{component}] #{operation} - #{format_details(details)}"
    else
      "[#{component}] #{operation}"
    end
  end
  
  @doc """
  Formats error log message with context.
  
  ## Examples
  
      iex> format_error("ESI", "fetch_failed", %{system_id: 123}, "timeout")
      "[ESI] ERROR: fetch_failed - system_id: 123 | error: timeout"
  """
  @spec format_error(String.t(), String.t(), map(), term()) :: String.t()
  def format_error(component, operation, context, error) do
    error_str = inspect(error)
    context_str = if map_size(context) > 0, do: format_details(context) <> " | ", else: ""
    
    "[#{component}] ERROR: #{operation} - #{context_str}error: #{error_str}"
  end
  
  # Private helpers
  
  defp format_details(details) do
    details
    |> Enum.map(fn {k, v} -> "#{k}: #{format_value(v)}" end)
    |> Enum.join(" | ")
  end
  
  defp format_value(value) when is_float(value), do: Float.round(value, 2)
  defp format_value(value) when is_binary(value) and byte_size(value) > 50 do
    String.slice(value, 0, 47) <> "..."
  end
  defp format_value(value), do: value
end