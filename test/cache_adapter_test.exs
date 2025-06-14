defmodule WandererKills.CacheAdapterTest do
  use ExUnit.Case, async: false

  alias WandererKills.Core.Cache

  test "basic cache operations work" do
    # Put a value
    result1 = Cache.put(:systems, "test_key", "test_value")
    assert {:ok, true} = result1

    # Get the value back
    result2 = Cache.get(:systems, "test_key")
    assert {:ok, "test_value"} = result2

    # Delete the value
    result3 = Cache.delete(:systems, "test_key")
    assert {:ok, _} = result3

    # Verify it's gone
    result4 = Cache.get(:systems, "test_key")
    assert {:error, _} = result4
  end
end
