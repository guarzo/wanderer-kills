defmodule WandererKills.ShipTypes.Validator do
  @moduledoc """
  Validation functions for ship types and groups data.

  This module provides validation logic to ensure ship type
  and group data integrity and correctness.
  """

  alias WandererKills.Support.Error

  @type ship_type :: map()
  @type ship_group :: map()
  @type validator_function :: (term() -> boolean())

  # Known ship group IDs (EVE Online ship categories)
  @ship_group_ids [
    25, 26, 27, 28, 29, 30, 31, 237, 324, 358, 380, 381, 419, 420, 463, 485, 513, 540, 541, 543,
    547, 659, 830, 831, 832, 833, 834, 883, 893, 894, 898, 900, 902, 906, 941, 963, 1022, 1201,
    1202, 1283, 1305, 1527, 1534, 1538, 1972, 2001
  ]

  @doc """
  Validates that a record has all required fields for a ship type.
  """
  @spec valid_ship_type?(ship_type()) :: boolean()
  def valid_ship_type?(ship_type) when is_map(ship_type) do
    with true <- is_integer(ship_type[:type_id]) and ship_type[:type_id] > 0,
         true <- is_binary(ship_type[:name]) and ship_type[:name] != "",
         true <- is_integer(ship_type[:group_id]) and ship_type[:group_id] > 0,
         true <- is_number(ship_type[:mass]) and ship_type[:mass] >= 0,
         true <- is_number(ship_type[:volume]) and ship_type[:volume] >= 0 do
      true
    else
      _ -> false
    end
  end

  def valid_ship_type?(_), do: false

  @doc """
  Validates that a record has all required fields for a ship group.
  """
  @spec valid_ship_group?(ship_group()) :: boolean()
  def valid_ship_group?(ship_group) when is_map(ship_group) do
    with true <- is_integer(ship_group[:group_id]) and ship_group[:group_id] > 0,
         true <- is_binary(ship_group[:name]) and ship_group[:name] != "",
         true <- is_integer(ship_group[:category_id]) and ship_group[:category_id] > 0 do
      true
    else
      _ -> false
    end
  end

  def valid_ship_group?(_), do: false

  @doc """
  Checks if a group ID represents a ship group.
  """
  @spec is_ship_group?(integer()) :: boolean()
  def is_ship_group?(group_id) when is_integer(group_id) do
    group_id in @ship_group_ids
  end

  def is_ship_group?(_), do: false

  @doc """
  Validates a parsed CSV record with custom validation function.
  """
  @spec validate_record(term(), validator_function()) :: {:ok, term()} | {:error, Error.t()}
  def validate_record(record, validator) do
    if validator.(record) do
      {:ok, record}
    else
      {:error,
       Error.validation_error(:invalid_record, "Record failed validation", %{
         record: inspect(record, limit: 5)
       })}
    end
  end

  @doc """
  Filters records based on validation function.
  """
  @spec filter_valid_records([term()], validator_function()) :: [term()]
  def filter_valid_records(records, validator) when is_list(records) do
    Enum.filter(records, validator)
  end

  @doc """
  Validates a batch of records and returns results with statistics.
  """
  @spec validate_batch([term()], validator_function()) ::
          {:ok, [term()], map()} | {:error, Error.t()}
  def validate_batch(records, validator) when is_list(records) do
    {valid, invalid} = Enum.split_with(records, validator)

    stats = %{
      total: length(records),
      valid: length(valid),
      invalid: length(invalid),
      validation_rate: if(length(records) > 0, do: length(valid) / length(records), else: 0.0)
    }

    if stats.validation_rate < 0.5 and length(records) > 10 do
      {:error,
       Error.validation_error(
         :low_validation_rate,
         "Too many records failed validation",
         stats
       )}
    else
      {:ok, valid, stats}
    end
  end

  @doc """
  Checks if a ship type belongs to a valid ship group.
  """
  @spec ship_type_in_valid_group?(ship_type()) :: boolean()
  def ship_type_in_valid_group?(ship_type) when is_map(ship_type) do
    is_ship_group?(ship_type[:group_id])
  end

  def ship_type_in_valid_group?(_), do: false

  @doc """
  Validates ship type data for caching.
  
  Ensures the ship type has all necessary fields for cache storage.
  """
  @spec valid_for_cache?(ship_type()) :: boolean()
  def valid_for_cache?(ship_type) when is_map(ship_type) do
    valid_ship_type?(ship_type) and
      ship_type_in_valid_group?(ship_type) and
      ship_type[:published] == true
  end

  def valid_for_cache?(_), do: false

  @doc """
  Returns the list of known ship group IDs.
  """
  @spec ship_group_ids() :: [integer()]
  def ship_group_ids, do: @ship_group_ids
end