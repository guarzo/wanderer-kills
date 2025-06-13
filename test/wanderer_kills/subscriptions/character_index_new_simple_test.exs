defmodule WandererKills.Subscriptions.CharacterIndexNewSimpleTest do
  use ExUnit.Case, async: false

  alias WandererKills.Subscriptions.CharacterIndexNew

  test "basic functionality works" do
    # Start the index 
    {:ok, pid} = CharacterIndexNew.start_link([])
    
    # Test basic operations
    CharacterIndexNew.add_subscription("sub_1", [123])
    result = CharacterIndexNew.find_subscriptions_for_entity(123)
    assert result == ["sub_1"]
    
    # Get stats
    stats = CharacterIndexNew.get_stats()
    assert stats.total_subscriptions == 1
    assert stats.total_character_entries == 1
    
    # Stop the GenServer
    GenServer.stop(pid)
  end
end