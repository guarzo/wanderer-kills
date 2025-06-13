defmodule WandererKills.Subscriptions.BaseIndexSimpleMacroTest do
  use ExUnit.Case, async: false

  # Create a minimal test module to verify the macro works
  defmodule TestIndex do
    use WandererKills.Subscriptions.BaseIndex,
      entity_type: :test_entity,
      table_name: :test_entity_simple_macro_index
  end

  test "simplified macro approach works" do
    # Start the test index GenServer
    {:ok, _pid} = TestIndex.start_link([])

    # Test the GenServer interface
    result = TestIndex.add_subscription("sub_1", [123, 456])
    assert result == :ok

    # Verify data was added
    subscriptions = TestIndex.find_subscriptions_for_entity(123)
    assert subscriptions == ["sub_1"]

    # Cleanup
    GenServer.stop(TestIndex)
  end
end
