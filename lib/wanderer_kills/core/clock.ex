defmodule WandererKills.Core.Clock do
  @moduledoc """
  Provides a configurable time interface for the application.

  This module allows time to be mocked in tests while providing
  real time values in production. It consolidates various time
  operations into a clean, testable interface.

  ## Configuration

  You can override the clock behavior in config/test.exs:

  ```elixir
  config :wanderer_kills, :clock, fn -> ~U[2025-01-01T00:00:00Z] end
  ```

  ## Usage

  ```elixir
  # Get current time
  now = Clock.now()

  # Get system time in various units
  ms = Clock.system_time(:millisecond)
  ns = Clock.system_time(:nanosecond)

  # Convenience functions
  iso = Clock.now_iso8601()
  past = Clock.hours_ago(2)
  ```
  """

  alias WandererKills.Config

  @type clock_config ::
          nil
          | {module(), atom()}
          | (-> DateTime.t() | integer())
          | DateTime.t()
          | integer()

  @doc """
  Returns the current `DateTime` in UTC.

  In production, this calls `DateTime.utc_now()`.
  In test mode, you can override via `:wanderer_kills, :clock`:

    * `{MyModule, :some_fun}`       – calls `apply(MyModule, :some_fun, [])`
    * `fn -> ~U[2025-01-01T00:00:00Z] end` – zero‐arity function
    * a `DateTime` struct
  """
  @spec now() :: DateTime.t()
  def now do
    case Config.clock() do
      nil ->
        DateTime.utc_now()

      {mod, fun} ->
        apply(mod, fun, [])

      fun when is_function(fun, 0) ->
        fun.()

      fixed_time when is_struct(fixed_time, DateTime) ->
        fixed_time
    end
  end

  @doc """
  Returns the current time in **milliseconds** since Unix epoch.

  In production, this calls `System.system_time(:millisecond)`.
  In test mode, the same `:wanderer_kills, :clock` variants apply:

    * `{MyModule, :some_fun}` returning a `DateTime` or integer
    * `fn -> DateTime` or `fn -> integer` (zero‐arity function)
    * a fixed `DateTime` (converted to ms)
    * a fixed integer (treated as ms already)
  """
  @spec now_milliseconds() :: integer()
  def now_milliseconds do
    case Config.clock() do
      nil ->
        System.system_time(:millisecond)

      {mod, fun} ->
        apply(mod, fun, [])
        |> datetime_or_int_to_milliseconds()

      fun when is_function(fun, 0) ->
        fun.() |> datetime_or_int_to_milliseconds()

      fixed_time when is_struct(fixed_time, DateTime) ->
        DateTime.to_unix(fixed_time, :millisecond)

      fixed_ms when is_integer(fixed_ms) ->
        fixed_ms
    end
  end

  @doc """
  Returns the current system time in **nanoseconds** by default.

  This zero-arity version simply delegates to `system_time(:nanosecond)`.
  """
  @spec system_time() :: integer()
  def system_time() do
    system_time(:nanosecond)
  end

  @doc """
  Returns the current system time in the specified `unit`.

  Valid units are `:second`, `:millisecond`, `:microsecond`, `:nanosecond`, or `:native`.
  """
  @spec system_time(System.time_unit()) :: integer()
  def system_time(unit) do
    get_system_time_with_config(unit)
  end

  @doc """
  Returns the current time as an ISO8601 string.
  """
  @spec now_iso8601() :: String.t()
  def now_iso8601 do
    now() |> DateTime.to_iso8601()
  end

  @doc """
  Returns a `DateTime` that is `seconds` seconds before the current `now()`.
  """
  @spec seconds_ago(non_neg_integer()) :: DateTime.t()
  def seconds_ago(seconds) do
    now() |> DateTime.add(-seconds, :second)
  end

  @doc """
  Returns a `DateTime` that is `hours` hours before the current `now()`.
  """
  @spec hours_ago(non_neg_integer()) :: DateTime.t()
  def hours_ago(hours) do
    now() |> DateTime.add(-hours * 3_600, :second)
  end

  #
  # ─── PRIVATE HELPERS ──────────────────────────────────────────────────────────
  #

  # Centralized system time logic with configuration support
  @spec get_system_time_with_config(System.time_unit()) :: integer()
  defp get_system_time_with_config(unit) do
    case Config.clock() do
      nil ->
        System.system_time(unit)

      {WandererKills.Core.Clock, :system_time} ->
        # Avoid recursion by calling System directly
        System.system_time(unit)

      config ->
        get_configured_time(config, unit)
    end
  end

  @spec get_configured_time(clock_config(), System.time_unit()) :: integer()
  defp get_configured_time({mod, fun}, unit) when is_atom(mod) and is_atom(fun) do
    apply(mod, fun, [])
    |> convert_time_to_unit(unit)
  end

  defp get_configured_time(fun, unit) when is_function(fun, 0) do
    fun.() |> convert_time_to_unit(unit)
  end

  defp get_configured_time(fixed_time, unit) when is_struct(fixed_time, DateTime) do
    convert_time_to_unit(fixed_time, unit)
  end

  defp get_configured_time(fixed_ms, unit) when is_integer(fixed_ms) do
    convert_time_to_unit(fixed_ms, unit)
  end

  # Catch-all: if the config is anything else, fall back to real System.system_time/1
  defp get_configured_time(_anything_else, unit) do
    System.system_time(unit)
  end

  @spec datetime_or_int_to_milliseconds(DateTime.t() | integer()) :: integer()
  defp datetime_or_int_to_milliseconds(%DateTime{} = dt) do
    DateTime.to_unix(dt, :millisecond)
  end

  defp datetime_or_int_to_milliseconds(ms) when is_integer(ms) do
    ms
  end

  @spec convert_time_to_unit(DateTime.t() | integer(), System.time_unit()) :: integer()
  defp convert_time_to_unit(%DateTime{} = dt, unit) do
    # If the caller asked for :native, interpret that as "nanoseconds since epoch"
    case unit do
      :native ->
        DateTime.to_unix(dt, :nanosecond)

      other_unit when other_unit in [:second, :millisecond, :microsecond, :nanosecond] ->
        DateTime.to_unix(dt, other_unit)
    end
  end

  defp convert_time_to_unit(time_ms, unit) when is_integer(time_ms) do
    # `time_ms` is always "ms since epoch" if it came from a fixed integer
    case unit do
      :millisecond ->
        time_ms

      :second ->
        div(time_ms, 1_000)

      :microsecond ->
        time_ms * 1_000

      :nanosecond ->
        time_ms * 1_000_000

      :native ->
        # Assume nanoseconds for :native
        time_ms * 1_000_000
    end
  end
end
