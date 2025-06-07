defmodule WandererKills.Infrastructure.Clock do
  @moduledoc """
  Unified time and clock utilities for WandererKills.

  This module consolidates all time-related functions from Infrastructure.Clock
  and TimeHandler modules, providing a single API for time operations.

  ## Configuration

  For testing, you can override the time source via application config:

  ```elixir
  # Use a fixed time
  config :wanderer_kills, :clock, ~U[2025-01-01T00:00:00Z]

  # Use a custom function
  config :wanderer_kills, :clock, fn -> DateTime.utc_now() end

  # Use a module and function
  config :wanderer_kills, :clock, {MyTimeModule, :current_time}
  ```

  ## Usage

  ```elixir
  # Get current time
  now = Clock.now()

  # Get milliseconds since epoch
  ms = Clock.now_milliseconds()

  # Get time N hours ago
  past = Clock.hours_ago(2)

  # Parse killmail times
  {:ok, datetime} = Clock.parse_time("2025-01-01T00:00:00Z")
  ```
  """

  require Logger
  alias WandererKills.Infrastructure.Config

  @type clock_config ::
          nil
          | {module(), atom()}
          | (-> DateTime.t() | integer())
          | DateTime.t()
          | integer()

  @type killmail :: map()
  @type time_result :: {:ok, DateTime.t()} | {:error, term()}
  @type validation_result :: {:ok, {killmail(), DateTime.t()}} | :older | :skip

  # ============================================================================
  # Current Time Functions
  # ============================================================================

  @doc """
  Returns the current `DateTime` in UTC.

  In production, this calls `DateTime.utc_now()`.
  In test mode, you can override via `:wanderer_kills, :clock`.
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
  """
  @spec system_time() :: integer()
  def system_time() do
    system_time(:nanosecond)
  end

  @doc """
  Returns the current system time in the specified `unit`.
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

  # ============================================================================
  # Relative Time Functions
  # ============================================================================

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

  @doc """
  Converts a DateTime to Unix timestamp in milliseconds.
  """
  @spec to_unix(DateTime.t()) :: integer()
  def to_unix(%DateTime{} = dt) do
    DateTime.to_unix(dt, :millisecond)
  end

  # ============================================================================
  # Time Parsing Functions (from TimeHandler)
  # ============================================================================

  @doc """
  Parses timestamps in a killmail.
  """
  @spec parse_times(killmail()) :: {:ok, killmail()} | {:error, term()}
  def parse_times(killmail) do
    with {:ok, kill_time} <- parse_kill_time(Map.get(killmail, "killTime")),
         {:ok, zkb_time} <- parse_zkb_time(get_in(killmail, ["zkb", "time"])) do
      killmail = Map.put(killmail, "killTime", kill_time)
      killmail = put_in(killmail, ["zkb", "time"], zkb_time)
      {:ok, killmail}
    else
      error ->
        Logger.error("Failed to parse times in killmail: #{inspect(error)}")
        error
    end
  end

  @doc """
  Validates and attaches a killmail's timestamp against a cutoff.
  Returns:
    - `{:ok, {km_with_time, dt}}` if valid
    - `:older` if timestamp is before cutoff
    - `:skip` if timestamp is missing or unparseable
  """
  @spec validate_killmail_time(killmail(), DateTime.t()) :: validation_result()
  def validate_killmail_time(km, cutoff_dt) do
    case get_killmail_time(km) do
      {:ok, km_dt} ->
        if older_than_cutoff?(km_dt, cutoff_dt) do
          :older
        else
          km_with_time = Map.put(km, "kill_time", km_dt)
          {:ok, {km_with_time, km_dt}}
        end

      {:error, reason} ->
        Logger.warning(
          "[Clock] Failed to parse time for killmail #{inspect(Map.get(km, "killmail_id"))}: #{inspect(reason)}"
        )

        :skip
    end
  end

  @doc """
  Gets the killmail time from any supported format.
  Returns `{:ok, DateTime.t()}` or `{:error, reason}`.
  """
  @spec get_killmail_time(killmail()) :: time_result()
  def get_killmail_time(%{"killmail_time" => value}), do: parse_time(value)
  def get_killmail_time(%{"killTime" => value}), do: parse_time(value)
  def get_killmail_time(%{"zkb" => %{"time" => value}}), do: parse_time(value)
  def get_killmail_time(_), do: {:error, :missing_time}

  @doc """
  Parses a time value from various formats into a DateTime.
  """
  @spec parse_time(String.t() | DateTime.t() | any()) :: time_result()
  def parse_time(dt) when is_struct(dt, DateTime), do: {:ok, dt}

  def parse_time(time_str) when is_binary(time_str) do
    case DateTime.from_iso8601(time_str) do
      {:ok, dt, _offset} ->
        {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}

      {:error, :invalid_format} ->
        case NaiveDateTime.from_iso8601(time_str) do
          {:ok, ndt} ->
            {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}

          error ->
            log_time_parse_error(time_str, error)
            error
        end

      error ->
        log_time_parse_error(time_str, error)
        error
    end
  end

  def parse_time(_), do: {:error, :invalid_time_format}

  @doc """
  Converts a DateTime to an ISO8601 string for storage in cache.
  """
  @spec datetime_to_string(DateTime.t() | any()) :: String.t() | nil
  def datetime_to_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def datetime_to_string(_), do: nil

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp parse_kill_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, datetime, _} -> {:ok, datetime}
      error -> error
    end
  end

  defp parse_kill_time(_), do: {:error, :invalid_kill_time}

  defp parse_zkb_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, datetime, _} -> {:ok, datetime}
      error -> error
    end
  end

  defp parse_zkb_time(_), do: {:error, :invalid_zkb_time}

  defp log_time_parse_error(time_str, error) do
    Logger.warning("[Clock] Failed to parse time: #{time_str}, error: #{inspect(error)}")
  end

  defp older_than_cutoff?(km_dt, cutoff_dt), do: DateTime.compare(km_dt, cutoff_dt) == :lt

  defp get_system_time_with_config(unit) do
    case Config.clock() do
      nil ->
        System.system_time(unit)

      {WandererKills.Clock, :system_time} ->
        # Avoid recursion by calling System directly
        System.system_time(unit)

      config ->
        get_configured_time(config, unit)
    end
  end

  @spec get_configured_time(clock_config(), System.time_unit()) :: integer()
  # Module function tuple - call and convert
  defp get_configured_time({mod, fun}, unit) when is_atom(mod) and is_atom(fun) do
    mod
    |> apply(fun, [])
    |> convert_time_to_unit(unit)
  end

  # Function reference - call and convert
  defp get_configured_time(fun, unit) when is_function(fun, 0) do
    fun
    |> apply([])
    |> convert_time_to_unit(unit)
  end

  # Fixed values - convert directly
  defp get_configured_time(value, unit) when is_struct(value, DateTime) or is_integer(value) do
    convert_time_to_unit(value, unit)
  end

  # Catch-all: fallback to system time
  defp get_configured_time(_config, unit) do
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
    DateTime.to_unix(dt, unit)
  end

  defp convert_time_to_unit(ms, :millisecond) when is_integer(ms), do: ms
  defp convert_time_to_unit(ms, :second) when is_integer(ms), do: div(ms, 1000)
  defp convert_time_to_unit(ms, :microsecond) when is_integer(ms), do: ms * 1000
  defp convert_time_to_unit(ms, :nanosecond) when is_integer(ms), do: ms * 1_000_000

  defp convert_time_to_unit(ms, :native) when is_integer(ms),
    do: System.convert_time_unit(ms, :millisecond, :native)
end
