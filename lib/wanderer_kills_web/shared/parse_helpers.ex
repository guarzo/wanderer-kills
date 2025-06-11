defmodule WandererKillsWeb.Shared.ParseHelpers do
  @moduledoc """
  Shared helper functions for parsing operations across web modules.
  """

  @doc """
  Safely parses a string to integer with a default fallback.

  ## Examples

      iex> parse_int("123")
      123

      iex> parse_int("abc")
      0

      iex> parse_int("123abc")
      123

      iex> parse_int("", 500)
      500

  """
  @spec parse_int(binary() | nil | integer(), integer()) :: integer()
  def parse_int(string, default \\ 0)

  def parse_int(string, default) when is_binary(string) do
    case Integer.parse(string) do
      {value, _rest} -> value
      :error -> default
    end
  end

  def parse_int(_string, default), do: default
end
