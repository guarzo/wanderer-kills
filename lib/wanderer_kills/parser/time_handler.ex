defmodule WandererKills.Parser.TimeHandler do
  @moduledoc """
  Handles time-related operations for killmails.
  """

  require Logger

  @type killmail :: map()
  @type time_result :: {:ok, DateTime.t()} | {:error, term()}
  @type validation_result :: {:ok, {killmail(), DateTime.t()}} | :older | :skip

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
          "[TimeHandler] Failed to parse time for killmail #{inspect(Map.get(km, "killmail_id"))}: #{inspect(reason)}"
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

  @spec parse_kill_time(String.t() | any()) :: time_result()
  defp parse_kill_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, datetime, _} -> {:ok, datetime}
      error -> error
    end
  end

  defp parse_kill_time(_), do: {:error, :invalid_kill_time}

  @spec parse_zkb_time(String.t() | any()) :: time_result()
  defp parse_zkb_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, datetime, _} -> {:ok, datetime}
      error -> error
    end
  end

  defp parse_zkb_time(_), do: {:error, :invalid_zkb_time}

  @spec parse_time(String.t() | DateTime.t() | any()) :: time_result()
  # If already a DateTime, just return it
  defp parse_time(dt) when is_struct(dt, DateTime), do: {:ok, dt}
  # If a string, try to parse as ISO8601 or NaiveDateTime
  defp parse_time(time_str) when is_binary(time_str) do
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

  # All other types are invalid
  defp parse_time(_), do: {:error, :invalid_time_format}

  @spec log_time_parse_error(String.t(), term()) :: :ok
  defp log_time_parse_error(time_str, error) do
    Logger.warning("[TimeHandler] Failed to parse time: #{time_str}, error: #{inspect(error)}")
  end

  @spec older_than_cutoff?(DateTime.t(), DateTime.t()) :: boolean()
  defp older_than_cutoff?(km_dt, cutoff_dt), do: DateTime.compare(km_dt, cutoff_dt) == :lt

  @doc """
  Converts a DateTime to an ISO8601 string for storage in cache.
  """
  @spec datetime_to_string(DateTime.t() | any()) :: String.t() | nil
  def datetime_to_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def datetime_to_string(_), do: nil
end
