defmodule WandererKills.Ingest.Killmails.Pipeline.Validator do
  @moduledoc """
  Comprehensive killmail validation that performs all checks in a single pass.

  This module combines structure validation, time validation, and
  cutoff checking into one efficient operation.
  """

  require Logger
  alias WandererKills.Core.Support.Error
  alias WandererKills.Ingest.Killmails.TimeFilters
  alias WandererKills.Domain.Killmail

  @type killmail :: map() | Killmail.t()
  @type validation_result :: %{
          valid: boolean(),
          killmail: killmail() | nil,
          errors: [Error.t()],
          warnings: [String.t()],
          metadata: map()
        }

  # Accept either kill_time or killmail_time since ESI returns killmail_time
  @required_fields ["killmail_id", "system_id", "victim", "attackers"]

  @doc """
  Performs all validations in a single pass.

  This includes:
  - Structure validation (required fields)
  - Type validation (field types)
  - Time parsing and validation
  - Cutoff time checking

  Returns a detailed result with all validation information.
  """
  @spec validate_killmail(killmail(), DateTime.t()) :: {:ok, killmail()} | {:error, Error.t()}
  def validate_killmail(%Killmail{} = killmail, cutoff_time) do
    # Structs are already validated during construction
    # Convert to map temporarily for time validation
    killmail_map = Killmail.to_map(killmail)

    case TimeFilters.validate_cutoff_time(killmail_map, cutoff_time) do
      :ok ->
        {:ok, killmail}

      {:error, _} ->
        {:error, Error.killmail_error(:kill_too_old, "Killmail is older than cutoff time")}
    end
  end

  def validate_killmail(killmail, cutoff_time) when is_map(killmail) do
    result = %{
      valid: true,
      killmail: killmail,
      errors: [],
      warnings: [],
      metadata: %{}
    }

    result
    |> validate_required_fields()
    |> validate_field_types()
    |> validate_and_parse_time(cutoff_time)
    |> finalize_validation()
  end

  def validate_killmail(_, _) do
    {:error, Error.validation_error(:invalid_input, "Killmail must be a map")}
  end

  # Private validation functions

  defp validate_required_fields(%{killmail: killmail} = result) do
    missing_fields =
      @required_fields
      |> Enum.reject(&Map.has_key?(killmail, &1))

    case missing_fields do
      [] ->
        result

      fields ->
        error =
          Error.killmail_error(
            :missing_required_fields,
            "Missing required fields: #{Enum.join(fields, ", ")}",
            false,
            %{missing_fields: fields}
          )

        %{
          result
          | valid: false,
            errors: [error | result.errors],
            metadata: Map.put(result.metadata, :missing_fields, fields)
        }
    end
  end

  defp validate_field_types(%{valid: false} = result), do: result

  defp validate_field_types(%{killmail: killmail} = result) do
    type_checks = [
      {:killmail_id, &is_integer/1, "must be an integer"},
      {:system_id, &is_integer/1, "must be an integer"},
      {:victim, &is_map/1, "must be a map"},
      {:attackers, &is_list/1, "must be a list"}
    ]

    type_errors = collect_type_errors(killmail, type_checks)

    case type_errors do
      [] ->
        result

      errors ->
        error =
          Error.validation_error(
            :invalid_field_types,
            "Invalid field types",
            %{type_errors: errors}
          )

        %{
          result
          | valid: false,
            errors: [error | result.errors],
            metadata: Map.put(result.metadata, :type_errors, errors)
        }
    end
  end

  defp collect_type_errors(killmail, type_checks) do
    Enum.reduce(type_checks, [], fn {field, validator, message}, errors ->
      value = Map.get(killmail, Atom.to_string(field))
      if validator.(value), do: errors, else: [{field, message} | errors]
    end)
  end

  defp validate_and_parse_time(%{valid: false} = result, _cutoff), do: result

  defp validate_and_parse_time(%{killmail: killmail} = result, cutoff_time) do
    case TimeFilters.extract_killmail_time(killmail) do
      {:ok, kill_time} ->
        case TimeFilters.validate_time_against_cutoff(kill_time, cutoff_time) do
          :ok ->
            # Valid time, add parsed version
            updated_killmail = Map.put(killmail, "parsed_kill_time", kill_time)

            %{
              result
              | killmail: updated_killmail,
                metadata: Map.put(result.metadata, :kill_time, kill_time)
            }

          {:error, error} ->
            %{
              result
              | valid: false,
                errors: [error | result.errors],
                metadata: Map.put(result.metadata, :kill_time, kill_time)
            }
        end

      {:error, error} ->
        %{result | valid: false, errors: [error | result.errors]}
    end
  end

  defp finalize_validation(%{valid: true, killmail: killmail}) do
    {:ok, killmail}
  end

  defp finalize_validation(%{errors: errors, killmail: killmail}) do
    # Get the first error for detailed logging
    first_error = List.first(errors)
    error_type = if first_error, do: first_error.type, else: :unknown
    error_message = if first_error, do: first_error.message, else: "Unknown error"

    # Check if this is just an old kill (not a real error)
    if error_type == :kill_too_old do
      Logger.debug("Killmail skipped - older than cutoff",
        killmail_id: killmail["killmail_id"],
        kill_time: killmail["kill_time"] || killmail["killmail_time"] || "none"
      )
    else
      # Log actual validation errors
      Logger.error("Killmail validation failed",
        killmail_id: killmail["killmail_id"],
        error_count: length(errors),
        error_type: error_type,
        error_message: error_message,
        killmail_keys: Map.keys(killmail) |> Enum.sort(),
        has_killmail_time: Map.has_key?(killmail, "killmail_time"),
        has_kill_time: Map.has_key?(killmail, "kill_time"),
        has_victim: Map.has_key?(killmail, "victim"),
        has_attackers: Map.has_key?(killmail, "attackers")
      )
    end

    # Return the first error for compatibility
    {:error, List.first(errors)}
  end

  @doc """
  Performs a quick validation check without full processing.

  Useful for pre-screening killmails before expensive operations.
  """
  @spec quick_validate(killmail()) :: boolean()
  def quick_validate(killmail) when is_map(killmail) do
    has_required_fields = Enum.all?(@required_fields, &Map.has_key?(killmail, &1))
    has_valid_id = is_integer(killmail["killmail_id"])

    has_required_fields and has_valid_id
  end

  def quick_validate(_), do: false

  @doc """
  Determines which validation step failed based on error type.

  This function helps with debugging and monitoring by categorizing
  validation failures into specific steps.
  """
  @spec determine_failure_step(term()) :: String.t()
  def determine_failure_step(%Error{type: :missing_required_fields}), do: "structure_validation"
  def determine_failure_step(%Error{type: :missing_killmail_id}), do: "structure_validation"
  def determine_failure_step(%Error{type: :invalid_field_types}), do: "type_validation"
  def determine_failure_step(%Error{type: :invalid_time_format}), do: "time_validation"
  def determine_failure_step(%Error{type: :missing_kill_time}), do: "time_validation"
  def determine_failure_step(%Error{type: :kill_too_old}), do: "time_check"
  def determine_failure_step(%Error{type: :build_failed}), do: "data_building"
  def determine_failure_step(_), do: "unknown"
end
