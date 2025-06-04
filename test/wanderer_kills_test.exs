defmodule WandererKillsTest do
  use ExUnit.Case
  doctest WandererKills

  test "version returns a string" do
    assert is_binary(WandererKills.version())
  end

  test "app_name returns :wanderer_kills" do
    assert WandererKills.app_name() == :wanderer_kills
  end
end
