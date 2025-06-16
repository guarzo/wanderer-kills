defmodule WandererKills.Subs.Subscriptions.CharacterIndexTest do
  use WandererKills.DataCase, async: false

  @moduletag :clear_indexes

  alias WandererKills.Subs.Subscriptions.CharacterIndex

  describe "add_subscription/2" do
    test "adds subscription with single character" do
      CharacterIndex.add_subscription("sub_1", [123])

      assert CharacterIndex.find_subscriptions_for_entity(123) == ["sub_1"]
      assert CharacterIndex.find_subscriptions_for_entity(456) == []
    end

    test "adds subscription with multiple characters" do
      CharacterIndex.add_subscription("sub_1", [123, 456, 789])

      assert CharacterIndex.find_subscriptions_for_entity(123) == ["sub_1"]
      assert CharacterIndex.find_subscriptions_for_entity(456) == ["sub_1"]
      assert CharacterIndex.find_subscriptions_for_entity(789) == ["sub_1"]
    end

    test "handles multiple subscriptions for same character" do
      CharacterIndex.add_subscription("sub_1", [123])
      CharacterIndex.add_subscription("sub_2", [123, 456])
      CharacterIndex.add_subscription("sub_3", [123])

      subs = CharacterIndex.find_subscriptions_for_entity(123)
      assert length(subs) == 3
      assert "sub_1" in subs
      assert "sub_2" in subs
      assert "sub_3" in subs
    end

    test "handles empty character list" do
      CharacterIndex.add_subscription("sub_1", [])

      stats = CharacterIndex.get_stats()
      assert stats.total_subscriptions == 1
      assert stats.total_character_entries == 0
    end
  end

  describe "update_subscription/2" do
    setup do
      CharacterIndex.add_subscription("sub_1", [123, 456])
      :ok
    end

    test "adds new characters to existing subscription" do
      CharacterIndex.update_subscription("sub_1", [123, 456, 789])

      assert CharacterIndex.find_subscriptions_for_entity(123) == ["sub_1"]
      assert CharacterIndex.find_subscriptions_for_entity(456) == ["sub_1"]
      assert CharacterIndex.find_subscriptions_for_entity(789) == ["sub_1"]
    end

    test "removes characters no longer in subscription" do
      CharacterIndex.update_subscription("sub_1", [123])

      assert CharacterIndex.find_subscriptions_for_entity(123) == ["sub_1"]
      assert CharacterIndex.find_subscriptions_for_entity(456) == []
    end

    test "completely changes character list" do
      CharacterIndex.update_subscription("sub_1", [789, 999])

      assert CharacterIndex.find_subscriptions_for_entity(123) == []
      assert CharacterIndex.find_subscriptions_for_entity(456) == []
      assert CharacterIndex.find_subscriptions_for_entity(789) == ["sub_1"]
      assert CharacterIndex.find_subscriptions_for_entity(999) == ["sub_1"]
    end

    test "handles updating to empty character list" do
      CharacterIndex.update_subscription("sub_1", [])

      assert CharacterIndex.find_subscriptions_for_entity(123) == []
      assert CharacterIndex.find_subscriptions_for_entity(456) == []

      stats = CharacterIndex.get_stats()
      assert stats.total_character_entries == 0
    end
  end

  describe "remove_subscription/1" do
    setup do
      CharacterIndex.add_subscription("sub_1", [123, 456])
      CharacterIndex.add_subscription("sub_2", [456, 789])
      :ok
    end

    test "removes subscription from all its characters" do
      CharacterIndex.remove_subscription("sub_1")

      assert CharacterIndex.find_subscriptions_for_entity(123) == []
      assert CharacterIndex.find_subscriptions_for_entity(456) == ["sub_2"]
      assert CharacterIndex.find_subscriptions_for_entity(789) == ["sub_2"]
    end

    test "cleans up character entries with no subscriptions" do
      CharacterIndex.remove_subscription("sub_1")
      CharacterIndex.remove_subscription("sub_2")

      assert CharacterIndex.find_subscriptions_for_entity(123) == []
      assert CharacterIndex.find_subscriptions_for_entity(456) == []
      assert CharacterIndex.find_subscriptions_for_entity(789) == []

      stats = CharacterIndex.get_stats()
      assert stats.total_character_entries == 0
    end

    test "handles removing non-existent subscription" do
      CharacterIndex.remove_subscription("sub_999")

      # Should not affect existing subscriptions
      assert CharacterIndex.find_subscriptions_for_entity(123) == ["sub_1"]
      assert length(CharacterIndex.find_subscriptions_for_entity(456)) == 2
    end
  end

  describe "find_subscriptions_for_entities/1" do
    setup do
      CharacterIndex.add_subscription("sub_1", [123, 456])
      CharacterIndex.add_subscription("sub_2", [456, 789])
      CharacterIndex.add_subscription("sub_3", [789, 999])
      :ok
    end

    test "finds all unique subscriptions for multiple characters" do
      subs = CharacterIndex.find_subscriptions_for_entities([123, 789])
      assert length(subs) == 3
      assert "sub_1" in subs
      assert "sub_2" in subs
      assert "sub_3" in subs
    end

    test "deduplicates subscription IDs" do
      # Both characters are in sub_2
      subs = CharacterIndex.find_subscriptions_for_entities([456, 789])
      assert length(subs) == 3
      assert "sub_1" in subs
      assert "sub_2" in subs
      assert "sub_3" in subs
    end

    test "returns empty list for unknown characters" do
      assert CharacterIndex.find_subscriptions_for_entities([111, 222]) == []
    end

    test "handles empty character list" do
      assert CharacterIndex.find_subscriptions_for_entities([]) == []
    end

    test "handles mix of known and unknown characters" do
      subs = CharacterIndex.find_subscriptions_for_entities([123, 111])
      assert subs == ["sub_1"]
    end
  end

  describe "get_stats/0" do
    test "returns correct statistics" do
      CharacterIndex.add_subscription("sub_1", [123, 456, 789])
      CharacterIndex.add_subscription("sub_2", [456, 789])
      CharacterIndex.add_subscription("sub_3", [])

      stats = CharacterIndex.get_stats()

      assert stats.total_subscriptions == 3
      # 123, 456, 789
      assert stats.total_character_entries == 3
      # 3 + 2 + 0
      assert stats.total_character_subscriptions == 5
    end
  end

  describe "performance" do
    test "handles large number of subscriptions efficiently" do
      # Add 1000 subscriptions, each with 10 characters
      for i <- 1..1000 do
        characters = Enum.to_list((i * 10)..(i * 10 + 9))
        CharacterIndex.add_subscription("sub_#{i}", characters)
      end

      # Time a lookup
      {time, result} =
        :timer.tc(fn ->
          CharacterIndex.find_subscriptions_for_entity(5005)
        end)

      assert result == ["sub_500"]
      # Should be very fast, under 1ms
      assert time < 1_000
    end

    test "handles lookups for characters with many subscriptions" do
      # Add 1000 subscriptions all interested in character 123
      for i <- 1..1000 do
        CharacterIndex.add_subscription("sub_#{i}", [123])
      end

      {time, result} =
        :timer.tc(fn ->
          CharacterIndex.find_subscriptions_for_entity(123)
        end)

      assert length(result) == 1000
      # Should still be fast even with many results
      assert time < 5_000
    end

    test "batch character lookup is efficient" do
      # Setup: 100 subscriptions with various characters
      for i <- 1..100 do
        characters = Enum.to_list((i * 100)..(i * 100 + 50))
        CharacterIndex.add_subscription("sub_#{i}", characters)
      end

      # Lookup subscriptions for 50 characters
      characters_to_find = Enum.to_list(150..199)

      {time, result} =
        :timer.tc(fn ->
          CharacterIndex.find_subscriptions_for_entities(characters_to_find)
        end)

      # Should find subscriptions efficiently
      assert length(result) > 0
      # Under 10ms for 50 character lookups
      assert time < 10_000
    end
  end
end
