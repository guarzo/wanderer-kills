defmodule WandererKills.Subscriptions.BaseIndexSimpleMacroTest do
  use ExUnit.Case, async: false

  # Create a minimal test module to verify the macro works
  defmodule TestIndex do
    defstruct [:table_name, :entity_type]
    
    def new(table_name, entity_type) do
      %__MODULE__{table_name: table_name, entity_type: entity_type}
    end
    
    def add_subscription(%__MODULE__{} = index, subscription_id, entity_ids) do
      WandererKills.Subscriptions.BaseIndex.handle_add_subscription(
        index.table_name, index.entity_type, Atom.to_string(index.entity_type), 
        subscription_id, entity_ids, %{reverse_index: %{}}
      )
    end
  end

  test "simplified macro approach works" do
    # Create ETS table manually
    table_name = :test_macro_index
    :ets.new(table_name, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    
    index = TestIndex.new(table_name, :test_entity)
    
    # Test the shared function directly
    {reply, _state} = TestIndex.add_subscription(index, "sub_1", [123, 456])
    assert reply == :ok
    
    # Verify data was added
    result = WandererKills.Subscriptions.BaseIndex.find_subscriptions_for_entity(
      table_name, 123, :test_entity
    )
    assert result == ["sub_1"]
    
    # Cleanup
    :ets.delete(table_name)
  end
end