defmodule WandererKills.Killmails.Pipeline.Validator do
  @moduledoc """
  Validation functions for killmail data.

  This module handles structural validation, time validation, and
  other checks needed to ensure killmail data integrity.
  """

  require Logger
  alias WandererKills.Support.Error

  @type killmail :: map()

  @doc """
  Validates killmail structure and time cutoff in a single pass.

  This function combines structure validation and time checking for efficiency.
  """
  @spec validate_killmail(killmail(), DateTime.t()) :: {:ok, killmail()} | {:error, Error.t()}
  def validate_killmail(killmail, cutoff_time) do
    with {:ok, validated_structure} <- validate_structure(killmail) do
      check_time_cutoff(validated_structure, cutoff_time)
    end
  end

  @doc """
  Validates the basic structure of a killmail.

  Ensures all required ESI fields are present.
  """
  @spec validate_structure(killmail()) :: {:ok, killmail()} | {:error, Error.t()}
  def validate_structure(%{"killmail_id" => id} = killmail) when is_integer(id) do
    required_fields = ["system_id", "victim", "attackers"]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(killmail, &1))

    if Enum.empty?(missing_fields) do
      {:ok, killmail}
    else
      Logger.error("[Validator] Killmail structure validation failed",
        killmail_id: id,
        required_fields: required_fields,
        missing_fields: missing_fields,
        available_keys: Map.keys(killmail),
        killmail_sample: killmail |> inspect(limit: 5, printable_limit: 200)
      )

      {:error,
       Error.killmail_error(
         :missing_required_fields,
         "Killmail missing required ESI fields",
         false,
         %{
           missing_fields: missing_fields,
           required_fields: required_fields
         }
       )}
    end
  end

  def validate_structure(killmail) when is_map(killmail) do
    Logger.error("[Validator] Killmail missing killmail_id field",
      available_keys: Map.keys(killmail),
      killmail_sample: killmail |> inspect(limit: 5, printable_limit: 200)
    )

    {:error, Error.killmail_error(:missing_killmail_id, "Killmail missing killmail_id field")}
  end

  @doc """
  Validates and parses killmail timestamp.
  """
  @spec validate_time(killmail()) :: {:ok, DateTime.t()} | {:error, Error.t()}
  def validate_time(%{"kill_time" => time}) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} ->
        {:ok, dt}

      {:error, reason} ->
        {:error,
         Error.killmail_error(:invalid_time_format, "Failed to parse ISO8601 timestamp", false, %{
           underlying_error: reason
         })}
    end
  end

  def validate_time(_),
    do: {:error, Error.killmail_error(:missing_kill_time, "Killmail missing valid time field")}

  @doc """
  Checks if killmail is newer than the cutoff time.
  """
  @spec check_time_cutoff(killmail(), DateTime.t()) :: {:ok, killmail()} | {:error, Error.t()}
  def check_time_cutoff(killmail, cutoff_time) do
    case validate_time(killmail) do
      {:ok, kill_time} ->
        if DateTime.compare(kill_time, cutoff_time) == :lt do
          Logger.debug("Killmail is older than cutoff",
            killmail_id: get_killmail_id(killmail),
            kill_time: DateTime.to_iso8601(kill_time),
            cutoff: DateTime.to_iso8601(cutoff_time)
          )

          {:error,
           Error.killmail_error(:kill_too_old, "Killmail is older than cutoff time", false, %{
             kill_time: DateTime.to_iso8601(kill_time),
             cutoff: DateTime.to_iso8601(cutoff_time)
           })}
        else
          {:ok, Map.put(killmail, "parsed_kill_time", kill_time)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Determines which validation step failed based on error type.
  """
  @spec determine_failure_step(term()) :: String.t()
  def determine_failure_step(%Error{type: :missing_required_fields}), do: "structure_validation"
  def determine_failure_step(%Error{type: :missing_killmail_id}), do: "structure_validation"
  def determine_failure_step(%Error{type: :invalid_time_format}), do: "time_validation"
  def determine_failure_step(%Error{type: :missing_kill_time}), do: "time_validation"
  def determine_failure_step(%Error{type: :kill_too_old}), do: "time_check"
  def determine_failure_step(%Error{type: :build_failed}), do: "data_building"
  def determine_failure_step(_), do: "unknown"

  defp get_killmail_id(%{"killmail_id" => id}) when is_integer(id), do: id
  defp get_killmail_id(_), do: nil
end
