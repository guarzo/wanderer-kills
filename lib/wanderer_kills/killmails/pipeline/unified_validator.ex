defmodule WandererKills.Killmails.Pipeline.UnifiedValidator do
  @moduledoc """
  Unified validation that performs all checks in a single pass.
  
  This module combines structure validation, time validation, and
  cutoff checking into one efficient operation.
  """
  
  require Logger
  alias WandererKills.Support.Error
  alias WandererKills.Killmails.TimeFilters
  
  @type killmail :: map()
  @type validation_result :: %{
    valid: boolean(),
    killmail: killmail() | nil,
    errors: [Error.t()],
    warnings: [String.t()],
    metadata: map()
  }
  
  @required_fields ["killmail_id", "solar_system_id", "victim", "attackers", "kill_time"]
  
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
        error = Error.killmail_error(
          :missing_required_fields,
          "Missing required fields: #{Enum.join(fields, ", ")}",
          false,
          %{missing_fields: fields}
        )
        
        %{result | 
          valid: false, 
          errors: [error | result.errors],
          metadata: Map.put(result.metadata, :missing_fields, fields)
        }
    end
  end
  
  defp validate_field_types(%{valid: false} = result), do: result
  
  defp validate_field_types(%{killmail: killmail} = result) do
    type_checks = [
      {:killmail_id, &is_integer/1, "must be an integer"},
      {:solar_system_id, &is_integer/1, "must be an integer"},
      {:victim, &is_map/1, "must be a map"},
      {:attackers, &is_list/1, "must be a list"}
    ]
    
    type_errors = collect_type_errors(killmail, type_checks)
    
    case type_errors do
      [] -> 
        result
        
      errors ->
        error = Error.validation_error(
          :invalid_field_types,
          "Invalid field types",
          %{type_errors: errors}
        )
        
        %{result | 
          valid: false, 
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
            %{result | 
              killmail: updated_killmail,
              metadata: Map.put(result.metadata, :kill_time, kill_time)
            }
            
          {:error, error} ->
            %{result | 
              valid: false, 
              errors: [error | result.errors],
              metadata: Map.put(result.metadata, :kill_time, kill_time)
            }
        end
        
      {:error, error} ->
        %{result | 
          valid: false, 
          errors: [error | result.errors]
        }
    end
  end
  
  defp finalize_validation(%{valid: true, killmail: killmail}) do
    {:ok, killmail}
  end
  
  defp finalize_validation(%{errors: errors, killmail: killmail}) do
    # Log all errors at once
    Logger.error("Killmail validation failed",
      killmail_id: killmail["killmail_id"],
      error_count: length(errors),
      errors: Enum.map(errors, &Error.to_map/1)
    )
    
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
end