defmodule WandererKills.Data.Parsers.CsvUtil do
  @moduledoc """
  Unified CSV parsing utilities for WandererKills.

  This module provides standardized CSV parsing functionality used across
  the application, including ship type data and other CSV-based data sources.
  """

  require Logger
  alias NimbleCSV.RFC4180, as: CSV

  @doc """
  Reads a CSV file and converts each row to a record using the provided parser function.
  Returns {:ok, records} or {:error, reason}
  """
  def read_rows(file_path, parser) do
    case File.read(file_path) do
      {:ok, content} ->
        try do
          # Parse the CSV content using NimbleCSV with headers included
          {headers, rows} =
            content
            |> CSV.parse_string(skip_headers: false)
            |> Enum.split(1)

          case headers do
            [header_row] when is_list(header_row) ->
              headers = Enum.map(header_row, &String.trim/1)

              records =
                rows
                |> Stream.map(&parse_row(&1, headers))
                |> Stream.map(&parser.(&1))
                |> Stream.reject(&is_nil/1)
                |> Enum.to_list()

              {:ok, records}

            _ ->
              {:error, :empty_file}
          end
        rescue
          e ->
            Logger.error("Failed to parse CSV file #{file_path}: #{inspect(e)}")
            {:error, :parse_error}
        end

      {:error, reason} ->
        Logger.error("Failed to read CSV file #{file_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Parses a CSV data row into a map using the provided headers.

  This is the unified row parsing function used across all CSV parsers
  in the application. It creates a map from the header row and data row.

  ## Parameters
  - `row` - List of values from a CSV row
  - `headers` - List of header names

  ## Returns
  Map with headers as keys and row values as values

  ## Examples

  ```elixir
  headers = ["id", "name", "value"]
  row = ["1", "test", "100"]
  result = parse_row(row, headers)
  # %{"id" => "1", "name" => "test", "value" => "100"}
  ```
  """
  @spec parse_row(list(String.t()), list(String.t())) :: map()
  def parse_row(row, headers) do
    headers
    |> Enum.zip(row)
    |> Map.new()
  end

  @doc """
  Parses a string value to integer, handling parse errors gracefully.

  ## Parameters
  - `value` - String value to parse

  ## Returns
  - `{:ok, integer}` on success
  - `{:error, :invalid_integer}` on failure
  """
  @spec parse_integer(String.t()) :: {:ok, integer()} | {:error, :invalid_integer}
  def parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  def parse_integer(_), do: {:error, :invalid_integer}

  @doc """
  Parses a string value to float, handling parse errors and scientific notation.

  ## Parameters
  - `value` - String value to parse

  ## Returns
  - `{:ok, float}` on success
  - `{:error, :invalid_float}` on failure
  """
  @spec parse_float(String.t()) :: {:ok, float()} | {:error, :invalid_float}
  def parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> {:ok, float}
      :error -> {:error, :invalid_float}
    end
  end

  def parse_float(_), do: {:error, :invalid_float}

  @doc """
  Parses a string value to float with a default value on error.

  ## Parameters
  - `value` - String value to parse
  - `default` - Default value to return on error (default: 0.0)

  ## Returns
  Float value or default
  """
  @spec parse_float_with_default(String.t(), float()) :: float()
  def parse_float_with_default(value, default \\ 0.0) do
    case parse_float(value) do
      {:ok, float} -> float
      {:error, _} -> default
    end
  end
end
