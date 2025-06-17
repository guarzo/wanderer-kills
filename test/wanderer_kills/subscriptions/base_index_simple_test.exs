defmodule WandererKills.Subs.Subscriptions.BaseIndexSimpleTest do
  use ExUnit.Case, async: false

  alias WandererKills.Subs.Subscriptions.BaseIndex

  # Simple test without the using macro to isolate the issue
  test "BaseIndex shared functions work correctly" do
    # Test table name for this test
    table_name = :test_simple_index

    # Create ETS table manually
    :ets.new(table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Test find_subscriptions_for_entity with empty table
    result =
      BaseIndex.find_subscriptions_for_entity(
        table_name,
        123,
        :test_entity
      )

    assert result == []

    # Manually insert some test data
    :ets.insert(table_name, {123, MapSet.new(["sub_1", "sub_2"])})

    # Test find_subscriptions_for_entity with data
    result =
      BaseIndex.find_subscriptions_for_entity(
        table_name,
        123,
        :test_entity
      )

    assert length(result) == 2
    assert "sub_1" in result
    assert "sub_2" in result

    # Test find_subscriptions_for_entities
    result =
      BaseIndex.find_subscriptions_for_entities(
        table_name,
        [123, 456],
        :test_entity
      )

    assert length(result) == 2
    assert "sub_1" in result
    assert "sub_2" in result

    # Test cleanup function
    :ets.insert(table_name, {456, MapSet.new([])})
    BaseIndex.cleanup_empty_entries(table_name)

    # Verify empty entry was removed
    assert :ets.lookup(table_name, 456) == []

    # Cleanup
    :ets.delete(table_name)
  end
end
