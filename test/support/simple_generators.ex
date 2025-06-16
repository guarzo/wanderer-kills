defmodule WandererKills.Test.SimpleGenerators do
  @moduledoc """
  Simple StreamData generators for property-based testing.
  """

  import StreamData

  @doc """
  Generates valid EVE Online system IDs.
  """
  def system_id, do: integer(30_000_000..31_000_000)

  @doc """
  Generates valid killmail IDs.
  """
  def killmail_id, do: integer(100_000_000..999_999_999)

  @doc """
  Generates simple cache keys.
  """
  def cache_key do
    one_of([
      constant("killmail:123456"),
      constant("system:30000142"),
      constant("test_key")
    ])
  end

  @doc """
  Generates simple cache values.
  """
  def cache_value do
    one_of([
      binary(),
      integer(),
      boolean(),
      constant(%{"test" => "value"})
    ])
  end

  @doc """
  Generates simple killmail data.
  """
  def simple_killmail do
    constant(%{
      "killmail_id" => 123_456_789,
      "solar_system_id" => 30_000_142,
      "killmail_time" => "2024-01-01T12:00:00Z",
      "victim" => %{"character_id" => 123, "damage_taken" => 100},
      "attackers" => [%{"character_id" => 456, "final_blow" => true}]
    })
  end
end
