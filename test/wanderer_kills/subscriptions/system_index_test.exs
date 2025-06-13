defmodule WandererKills.Subscriptions.SystemIndexTest do
  use ExUnit.Case, async: false

  alias WandererKills.Subscriptions.SystemIndex

  setup do
    # Ensure clean state
    SystemIndex.clear()

    on_exit(fn ->
      SystemIndex.clear()
    end)

    :ok
  end

  describe "add_subscription/2" do
    test "adds subscription with single system" do
      SystemIndex.add_subscription("sub_1", [30_000_142])

      assert SystemIndex.find_subscriptions_for_entity(30_000_142) == ["sub_1"]
      assert SystemIndex.find_subscriptions_for_entity(30_000_144) == []
    end

    test "adds subscription with multiple systems" do
      SystemIndex.add_subscription("sub_1", [30_000_142, 30_000_144, 30_000_148])

      assert SystemIndex.find_subscriptions_for_entity(30_000_142) == ["sub_1"]
      assert SystemIndex.find_subscriptions_for_entity(30_000_144) == ["sub_1"]
      assert SystemIndex.find_subscriptions_for_entity(30_000_148) == ["sub_1"]
    end

    test "handles multiple subscriptions for same system" do
      SystemIndex.add_subscription("sub_1", [30_000_142])
      SystemIndex.add_subscription("sub_2", [30_000_142, 30_000_144])
      SystemIndex.add_subscription("sub_3", [30_000_142])

      subs = SystemIndex.find_subscriptions_for_entity(30_000_142)
      assert length(subs) == 3
      assert "sub_1" in subs
      assert "sub_2" in subs
      assert "sub_3" in subs
    end

    test "handles empty system list" do
      SystemIndex.add_subscription("sub_1", [])

      stats = SystemIndex.get_stats()
      assert stats.total_subscriptions == 1
      assert stats.total_system_entries == 0
    end
  end

  describe "update_subscription/2" do
    setup do
      SystemIndex.add_subscription("sub_1", [30_000_142, 30_000_144])
      :ok
    end

    test "adds new systems to existing subscription" do
      SystemIndex.update_subscription("sub_1", [30_000_142, 30_000_144, 30_000_148])

      assert SystemIndex.find_subscriptions_for_entity(30_000_142) == ["sub_1"]
      assert SystemIndex.find_subscriptions_for_entity(30_000_144) == ["sub_1"]
      assert SystemIndex.find_subscriptions_for_entity(30_000_148) == ["sub_1"]
    end

    test "removes systems no longer in subscription" do
      SystemIndex.update_subscription("sub_1", [30_000_142])

      assert SystemIndex.find_subscriptions_for_entity(30_000_142) == ["sub_1"]
      assert SystemIndex.find_subscriptions_for_entity(30_000_144) == []
    end

    test "completely changes system list" do
      SystemIndex.update_subscription("sub_1", [30_000_148, 30_000_999])

      assert SystemIndex.find_subscriptions_for_entity(30_000_142) == []
      assert SystemIndex.find_subscriptions_for_entity(30_000_144) == []
      assert SystemIndex.find_subscriptions_for_entity(30_000_148) == ["sub_1"]
      assert SystemIndex.find_subscriptions_for_entity(30_000_999) == ["sub_1"]
    end

    test "handles updating to empty system list" do
      SystemIndex.update_subscription("sub_1", [])

      assert SystemIndex.find_subscriptions_for_entity(30_000_142) == []
      assert SystemIndex.find_subscriptions_for_entity(30_000_144) == []

      stats = SystemIndex.get_stats()
      assert stats.total_system_entries == 0
    end
  end

  describe "remove_subscription/1" do
    setup do
      SystemIndex.add_subscription("sub_1", [30_000_142, 30_000_144])
      SystemIndex.add_subscription("sub_2", [30_000_144, 30_000_148])
      :ok
    end

    test "removes subscription from all its systems" do
      SystemIndex.remove_subscription("sub_1")

      assert SystemIndex.find_subscriptions_for_entity(30_000_142) == []
      assert SystemIndex.find_subscriptions_for_entity(30_000_144) == ["sub_2"]
      assert SystemIndex.find_subscriptions_for_entity(30_000_148) == ["sub_2"]
    end

    test "cleans up system entries with no subscriptions" do
      SystemIndex.remove_subscription("sub_1")
      SystemIndex.remove_subscription("sub_2")

      assert SystemIndex.find_subscriptions_for_entity(30_000_142) == []
      assert SystemIndex.find_subscriptions_for_entity(30_000_144) == []
      assert SystemIndex.find_subscriptions_for_entity(30_000_148) == []

      stats = SystemIndex.get_stats()
      assert stats.total_system_entries == 0
    end

    test "handles removing non-existent subscription" do
      SystemIndex.remove_subscription("sub_999")

      # Should not affect existing subscriptions
      assert SystemIndex.find_subscriptions_for_entity(30_000_142) == ["sub_1"]
      assert length(SystemIndex.find_subscriptions_for_entity(30_000_144)) == 2
    end
  end

  describe "find_subscriptions_for_entities/1" do
    setup do
      SystemIndex.add_subscription("sub_1", [30_000_142, 30_000_144])
      SystemIndex.add_subscription("sub_2", [30_000_144, 30_000_148])
      SystemIndex.add_subscription("sub_3", [30_000_148, 30_000_999])
      :ok
    end

    test "finds all unique subscriptions for multiple systems" do
      subs = SystemIndex.find_subscriptions_for_entities([30_000_142, 30_000_148])
      assert length(subs) == 3
      assert "sub_1" in subs
      assert "sub_2" in subs
      assert "sub_3" in subs
    end

    test "deduplicates subscription IDs" do
      # Both systems are in sub_2
      subs = SystemIndex.find_subscriptions_for_entities([30_000_144, 30_000_148])
      assert length(subs) == 3
      assert "sub_1" in subs
      assert "sub_2" in subs
      assert "sub_3" in subs
    end

    test "returns empty list for unknown systems" do
      assert SystemIndex.find_subscriptions_for_entities([30_001_111, 30_002_222]) == []
    end

    test "handles empty system list" do
      assert SystemIndex.find_subscriptions_for_entities([]) == []
    end

    test "handles mix of known and unknown systems" do
      subs = SystemIndex.find_subscriptions_for_entities([30_000_142, 30_001_111])
      assert subs == ["sub_1"]
    end
  end

  describe "get_stats/0" do
    test "returns correct statistics" do
      SystemIndex.add_subscription("sub_1", [30_000_142, 30_000_144, 30_000_148])
      SystemIndex.add_subscription("sub_2", [30_000_144, 30_000_148])
      SystemIndex.add_subscription("sub_3", [])

      stats = SystemIndex.get_stats()

      assert stats.total_subscriptions == 3
      # 30000142, 30000144, 30000148
      assert stats.total_system_entries == 3
      assert is_number(stats.memory_usage_bytes)
    end
  end

  describe "performance" do
    test "handles large number of subscriptions efficiently" do
      # Add 1000 subscriptions, each with 10 systems
      for i <- 1..1000 do
        systems = Enum.to_list((30_000_000 + i * 10)..(30_000_000 + i * 10 + 9))
        SystemIndex.add_subscription("sub_#{i}", systems)
      end

      # Time a lookup
      {time, result} =
        :timer.tc(fn ->
          SystemIndex.find_subscriptions_for_entity(30_005_005)
        end)

      assert result == ["sub_500"]
      # Should be very fast, under 1ms
      assert time < 1_000
    end

    test "handles lookups for systems with many subscriptions" do
      # Add 1000 subscriptions all interested in system 30000142
      for i <- 1..1000 do
        SystemIndex.add_subscription("sub_#{i}", [30_000_142])
      end

      {time, result} =
        :timer.tc(fn ->
          SystemIndex.find_subscriptions_for_entity(30_000_142)
        end)

      assert length(result) == 1000
      # Should still be fast even with many results
      assert time < 5_000
    end

    test "batch system lookup is efficient" do
      # Setup: 100 subscriptions with various systems
      for i <- 1..100 do
        systems = Enum.to_list((30_000_000 + i * 100)..(30_000_000 + i * 100 + 50))
        SystemIndex.add_subscription("sub_#{i}", systems)
      end

      # Lookup subscriptions for 50 systems
      systems_to_find = Enum.to_list(30_000_150..30_000_199)

      {time, result} =
        :timer.tc(fn ->
          SystemIndex.find_subscriptions_for_entities(systems_to_find)
        end)

      # Should find subscriptions efficiently
      assert length(result) > 0
      # Under 10ms for 50 system lookups
      assert time < 10_000
    end
  end
end
