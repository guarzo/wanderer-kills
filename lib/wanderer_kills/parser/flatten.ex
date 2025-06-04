defmodule WandererKills.Parser.Flatten do
  @moduledoc """
  Provides functionality for flattening nested fields in killmail data.
  """

  @doc """
  Flattens nested fields in a map according to the provided mappings.

  ## Parameters
  - `map` - The source map containing nested fields
  - `prefix` - The prefix to use for flattened field names
  - `mappings` - List of {source_key, suffix} tuples defining how to flatten fields

  ## Returns
  A new map with flattened fields.

  ## Examples

  ```elixir
  source = %{
    "character_id" => 123,
    "corporation_id" => 456
  }
  mappings = [
    {"character_id", "char_id"},
    {"corporation_id", "corp_id"}
  ]

  Flatten.flatten_keys(source, "victim", mappings)
  # => %{
  #   "victim_char_id" => 123,
  #   "victim_corp_id" => 456
  # }
  ```
  """
  @spec flatten_keys(map(), String.t(), [{String.t(), String.t()}]) :: map()
  def flatten_keys(map, prefix, mappings) do
    Enum.reduce(mappings, %{}, fn {src_key, suffix}, acc ->
      case Map.fetch(map, src_key) do
        {:ok, val} -> Map.put(acc, "#{prefix}_#{suffix}", val)
        :error -> acc
      end
    end)
  end

  @doc """
  Flattens fields in a map using predefined mappings for killmail data.

  ## Parameters
  - `map` - The source map containing nested fields
  - `prefix` - The prefix to use for flattened field names

  ## Returns
  A new map with flattened fields.

  ## Examples

  ```elixir
  source = %{
    "character_id" => 123,
    "corporation_id" => 456,
    "alliance_id" => 789,
    "ship_type_id" => 101
  }

  Flatten.flatten_fields(source, "victim")
  # => %{
  #   "victim_char_id" => 123,
  #   "victim_corp_id" => 456,
  #   "victim_alliance_id" => 789,
  #   "victim_ship_type_id" => 101
  # }
  ```
  """
  @spec flatten_fields(map(), String.t()) :: map()
  def flatten_fields(map, prefix) do
    mappings = [
      {"character_id", "char_id"},
      {"corporation_id", "corp_id"},
      {"alliance_id", "alliance_id"},
      {"ship_type_id", "ship_type_id"}
    ]

    flatten_keys(map, prefix, mappings)
  end
end
