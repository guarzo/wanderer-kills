defmodule WandererKills.Ingest.Killmails.BatchProcessorTest do
  use ExUnit.Case, async: true

  alias WandererKills.Ingest.Killmails.BatchProcessor
  alias WandererKills.Ingest.Killmails.CharacterCache
  alias WandererKills.Subs.Subscriptions.CharacterIndex

  setup do
    # Ensure clean state
    CharacterIndex.clear()
    CharacterCache.clear_cache()

    on_exit(fn ->
      CharacterIndex.clear()
      CharacterCache.clear_cache()
    end)

    :ok
  end

  describe "extract_all_characters/1" do
    test "extracts characters from multiple killmails" do
      killmails = [
        %{
          "killmail_id" => 1,
          "victim" => %{"character_id" => 123},
          "attackers" => [
            %{"character_id" => 456},
            %{"character_id" => 789}
          ]
        },
        %{
          "killmail_id" => 2,
          # Duplicate
          "victim" => %{"character_id" => 456},
          "attackers" => [
            %{"character_id" => 999}
          ]
        }
      ]

      result = BatchProcessor.extract_all_characters(killmails)

      assert MapSet.size(result) == 4
      assert 123 in result
      assert 456 in result
      assert 789 in result
      assert 999 in result
    end

    test "handles empty killmails list" do
      assert BatchProcessor.extract_all_characters([]) == MapSet.new()
    end

    test "handles killmails with missing character data" do
      killmails = [
        %{"killmail_id" => 1, "victim" => %{}},
        %{"killmail_id" => 2, "attackers" => []},
        %{"killmail_id" => 3}
      ]

      result = BatchProcessor.extract_all_characters(killmails)
      assert MapSet.size(result) == 0
    end

    test "processes large batches efficiently" do
      # Create 1000 killmails with 10 attackers each
      killmails =
        for i <- 1..1000 do
          %{
            "killmail_id" => i,
            "victim" => %{"character_id" => i},
            "attackers" => Enum.map(1..10, fn j -> %{"character_id" => i * 1000 + j} end)
          }
        end

      {time, result} =
        :timer.tc(fn ->
          BatchProcessor.extract_all_characters(killmails)
        end)

      # Should extract 11,000 unique characters (1 victim + 10 attackers per killmail)
      assert MapSet.size(result) == 11_000

      # Should complete reasonably quickly even with 1000 killmails
      # Less than 1 second
      assert time < 1_000_000
    end
  end

  describe "match_killmails_to_subscriptions/2" do
    test "matches killmails to subscriptions based on characters" do
      killmails = [
        %{
          "killmail_id" => 1,
          "victim" => %{"character_id" => 123},
          "attackers" => []
        },
        %{
          "killmail_id" => 2,
          "victim" => %{"character_id" => 456},
          "attackers" => []
        },
        %{
          "killmail_id" => 3,
          "victim" => %{"character_id" => 789},
          "attackers" => []
        }
      ]

      subscription_character_map = %{
        "sub_1" => [123, 456],
        "sub_2" => [456, 789],
        # No matches
        "sub_3" => [999]
      }

      result =
        BatchProcessor.match_killmails_to_subscriptions(killmails, subscription_character_map)

      assert length(result["sub_1"]) == 2
      assert Enum.any?(result["sub_1"], &(&1["killmail_id"] == 1))
      assert Enum.any?(result["sub_1"], &(&1["killmail_id"] == 2))

      assert length(result["sub_2"]) == 2
      assert Enum.any?(result["sub_2"], &(&1["killmail_id"] == 2))
      assert Enum.any?(result["sub_2"], &(&1["killmail_id"] == 3))

      refute Map.has_key?(result, "sub_3")
    end

    test "handles empty inputs" do
      assert BatchProcessor.match_killmails_to_subscriptions([], %{}) == %{}
      assert BatchProcessor.match_killmails_to_subscriptions([%{"killmail_id" => 1}], %{}) == %{}
      assert BatchProcessor.match_killmails_to_subscriptions([], %{"sub_1" => [123]}) == %{}
    end

    test "matches based on attacker characters" do
      killmails = [
        %{
          "killmail_id" => 1,
          "victim" => %{"character_id" => 111},
          "attackers" => [
            %{"character_id" => 123},
            %{"character_id" => 456}
          ]
        }
      ]

      subscription_character_map = %{
        "sub_1" => [123],
        "sub_2" => [456],
        # Victim match
        "sub_3" => [111]
      }

      result =
        BatchProcessor.match_killmails_to_subscriptions(killmails, subscription_character_map)

      assert Map.has_key?(result, "sub_1")
      assert Map.has_key?(result, "sub_2")
      assert Map.has_key?(result, "sub_3")
      assert length(result["sub_1"]) == 1
      assert length(result["sub_2"]) == 1
      assert length(result["sub_3"]) == 1
    end
  end

  describe "find_interested_subscriptions/1" do
    setup do
      # Add some subscriptions to the CharacterIndex
      CharacterIndex.add_subscription("sub_1", [123, 456])
      CharacterIndex.add_subscription("sub_2", [456, 789])
      CharacterIndex.add_subscription("sub_3", [999])
      :ok
    end

    test "finds subscriptions interested in killmails" do
      killmails = [
        %{
          "killmail_id" => 1,
          "victim" => %{"character_id" => 123},
          "attackers" => []
        },
        %{
          "killmail_id" => 2,
          "victim" => %{"character_id" => 789},
          "attackers" => []
        },
        %{
          "killmail_id" => 3,
          # No subscription
          "victim" => %{"character_id" => 111},
          "attackers" => []
        }
      ]

      result = BatchProcessor.find_interested_subscriptions(killmails)

      assert "sub_1" in result[1]
      assert "sub_2" in result[2]
      refute Map.has_key?(result, 3)
    end

    test "finds multiple subscriptions for same killmail" do
      killmail = [
        %{
          "killmail_id" => 1,
          # Both sub_1 and sub_2
          "victim" => %{"character_id" => 456},
          "attackers" => []
        }
      ]

      result = BatchProcessor.find_interested_subscriptions(killmail)

      assert length(result[1]) == 2
      assert "sub_1" in result[1]
      assert "sub_2" in result[1]
    end

    test "handles empty killmails" do
      assert BatchProcessor.find_interested_subscriptions([]) == %{}
    end
  end

  describe "group_killmails_by_subscription/2" do
    setup do
      # Add subscriptions to the CharacterIndex
      CharacterIndex.add_subscription("sub_1", [123, 456])
      CharacterIndex.add_subscription("sub_2", [456, 789])
      :ok
    end

    test "groups killmails by interested subscriptions" do
      killmails = [
        %{
          "killmail_id" => 1,
          "victim" => %{"character_id" => 123},
          "attackers" => []
        },
        %{
          "killmail_id" => 2,
          "victim" => %{"character_id" => 456},
          "attackers" => []
        },
        %{
          "killmail_id" => 3,
          "victim" => %{"character_id" => 789},
          "attackers" => []
        }
      ]

      subscriptions = %{
        "sub_1" => %{"id" => "sub_1", "system_ids" => [], "character_ids" => [123, 456]},
        "sub_2" => %{"id" => "sub_2", "system_ids" => [], "character_ids" => [456, 789]}
      }

      result = BatchProcessor.group_killmails_by_subscription(killmails, subscriptions)

      # sub_1 should have killmails 1 and 2 (characters 123 and 456)
      assert length(result["sub_1"]) == 2
      assert Enum.any?(result["sub_1"], &(&1["killmail_id"] == 1))
      assert Enum.any?(result["sub_1"], &(&1["killmail_id"] == 2))

      # sub_2 should have killmails 2 and 3 (characters 456 and 789)
      assert length(result["sub_2"]) == 2
      assert Enum.any?(result["sub_2"], &(&1["killmail_id"] == 2))
      assert Enum.any?(result["sub_2"], &(&1["killmail_id"] == 3))
    end

    test "ignores subscriptions not in the provided map" do
      CharacterIndex.add_subscription("sub_3", [999])

      killmails = [
        %{
          "killmail_id" => 1,
          "victim" => %{"character_id" => 999},
          "attackers" => []
        }
      ]

      # Only include sub_1 and sub_2 in subscriptions map
      subscriptions = %{
        "sub_1" => %{"id" => "sub_1", "system_ids" => [], "character_ids" => [123, 456]},
        "sub_2" => %{"id" => "sub_2", "system_ids" => [], "character_ids" => [456, 789]}
      }

      result = BatchProcessor.group_killmails_by_subscription(killmails, subscriptions)

      # sub_3 is not included, so killmail should not appear
      refute Map.has_key?(result, "sub_3")
      assert result == %{}
    end

    test "handles empty inputs" do
      assert BatchProcessor.group_killmails_by_subscription([], %{}) == %{}
    end
  end

  describe "performance benchmarks" do
    test "handles large batches with many subscriptions" do
      # Setup: 100 subscriptions with various characters
      for i <- 1..100 do
        characters = Enum.to_list((i * 10)..(i * 10 + 9))
        CharacterIndex.add_subscription("sub_#{i}", characters)
      end

      # Create 500 killmails with various characters
      killmails =
        for i <- 1..500 do
          %{
            "killmail_id" => i,
            "victim" => %{"character_id" => rem(i, 1000)},
            "attackers" => Enum.map(1..5, fn j -> %{"character_id" => rem(i * j, 1000)} end)
          }
        end

      subscriptions =
        Map.new(1..100, fn i ->
          characters = Enum.to_list((i * 10)..(i * 10 + 9))
          {"sub_#{i}", %{"id" => "sub_#{i}", "system_ids" => [], "character_ids" => characters}}
        end)

      {time, result} =
        :timer.tc(fn ->
          BatchProcessor.group_killmails_by_subscription(killmails, subscriptions)
        end)

      # Should complete efficiently
      assert map_size(result) > 0
      # Less than 5 seconds for 500 killmails
      assert time < 5_000_000

      # Verify some subscriptions got matches
      assert Enum.any?(result, fn {_sub_id, kills} -> length(kills) > 0 end)
    end
  end
end
