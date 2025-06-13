defmodule WandererKills.Subscriptions.CharacterIndexNewTest do
  use ExUnit.Case, async: false

  alias WandererKills.Subscriptions.CharacterIndexNew

  setup do
    # Start the index if not already running
    case GenServer.whereis(CharacterIndexNew) do
      nil -> 
        {:ok, _pid} = CharacterIndexNew.start_link([])
      _pid -> 
        :ok
    end
    
    # Clear the index before each test
    CharacterIndexNew.clear()

    on_exit(fn ->
      CharacterIndexNew.clear()
    end)

    :ok
  end

  describe "basic functionality" do
    test "adds subscription with single character" do
      CharacterIndexNew.add_subscription("sub_1", [123])

      assert CharacterIndexNew.find_subscriptions_for_entity(123) == ["sub_1"]
      assert CharacterIndexNew.find_subscriptions_for_entity(456) == []
    end

    test "adds subscription with multiple characters" do
      CharacterIndexNew.add_subscription("sub_1", [123, 456, 789])

      assert CharacterIndexNew.find_subscriptions_for_entity(123) == ["sub_1"]
      assert CharacterIndexNew.find_subscriptions_for_entity(456) == ["sub_1"]
      assert CharacterIndexNew.find_subscriptions_for_entity(789) == ["sub_1"]
    end

    test "handles multiple subscriptions for same character" do
      CharacterIndexNew.add_subscription("sub_1", [123])
      CharacterIndexNew.add_subscription("sub_2", [123, 456])
      CharacterIndexNew.add_subscription("sub_3", [123])

      subs = CharacterIndexNew.find_subscriptions_for_entity(123)
      assert length(subs) == 3
      assert "sub_1" in subs
      assert "sub_2" in subs
      assert "sub_3" in subs
    end

    test "handles empty character list" do
      CharacterIndexNew.add_subscription("sub_1", [])

      stats = CharacterIndexNew.get_stats()
      assert stats.total_subscriptions == 1
      assert stats.total_character_entries == 0
    end
  end

  describe "get_stats/0" do
    test "returns correct statistics with unified format" do
      CharacterIndexNew.add_subscription("sub_1", [123, 456, 789])
      CharacterIndexNew.add_subscription("sub_2", [456, 789])
      CharacterIndexNew.add_subscription("sub_3", [])

      stats = CharacterIndexNew.get_stats()

      assert stats.total_subscriptions == 3
      # 123, 456, 789
      assert stats.total_character_entries == 3
      # 3 + 2 + 0
      assert stats.total_character_subscriptions == 5
      assert is_number(stats.memory_usage_bytes)
      assert stats.memory_usage_bytes > 0
    end
  end

  describe "performance" do
    test "handles large number of subscriptions efficiently" do
      # Add 500 subscriptions, each with 10 characters  
      for i <- 1..500 do
        characters = Enum.to_list((i * 10)..(i * 10 + 9))
        CharacterIndexNew.add_subscription("sub_#{i}", characters)
      end

      # Time a lookup
      {time, result} =
        :timer.tc(fn ->
          CharacterIndexNew.find_subscriptions_for_entity(2505)
        end)

      assert result == ["sub_250"]
      # Should be very fast, under 1ms
      assert time < 1_000
    end
  end
end