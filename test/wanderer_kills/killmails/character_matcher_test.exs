defmodule WandererKills.Killmails.CharacterMatcherTest do
  use ExUnit.Case, async: true

  alias WandererKills.Killmails.CharacterMatcher

  # Helper function to build killmail maps with victim and attackers
  defp build_killmail(victim_id, attacker_ids) do
    victim = if victim_id, do: %{"character_id" => victim_id}, else: nil
    attackers = Enum.map(attacker_ids, fn id -> %{"character_id" => id} end)

    %{
      "victim" => victim,
      "attackers" => attackers
    }
  end

  describe "killmail_has_characters?/2" do
    test "returns true when victim matches" do
      killmail = build_killmail(123, [])

      assert CharacterMatcher.killmail_has_characters?(killmail, [123, 456])
      assert CharacterMatcher.killmail_has_characters?(killmail, [123])
    end

    test "returns true when attacker matches" do
      killmail = build_killmail(999, [123, 456])

      assert CharacterMatcher.killmail_has_characters?(killmail, [123])
      assert CharacterMatcher.killmail_has_characters?(killmail, [456])
      assert CharacterMatcher.killmail_has_characters?(killmail, [789, 123])
    end

    test "returns true when both victim and attacker match" do
      killmail = build_killmail(123, [456, 789])

      assert CharacterMatcher.killmail_has_characters?(killmail, [123, 456])
    end

    test "returns false when no matches found" do
      killmail = build_killmail(123, [456, 789])

      refute CharacterMatcher.killmail_has_characters?(killmail, [111, 222, 333])
    end

    test "returns false for empty character_ids list" do
      killmail = build_killmail(123, [])

      refute CharacterMatcher.killmail_has_characters?(killmail, [])
    end

    test "returns false for nil character_ids" do
      killmail = build_killmail(123, [])

      refute CharacterMatcher.killmail_has_characters?(killmail, nil)
    end

    test "handles missing victim character_id" do
      killmail = build_killmail(nil, [123])

      assert CharacterMatcher.killmail_has_characters?(killmail, [123])
      refute CharacterMatcher.killmail_has_characters?(killmail, [456])
    end

    test "handles missing attacker character_id" do
      # Create custom killmail for this edge case with mixed attackers
      killmail = %{
        "victim" => %{"character_id" => 123},
        "attackers" => [
          # attacker without character_id
          %{},
          %{"character_id" => 456}
        ]
      }

      assert CharacterMatcher.killmail_has_characters?(killmail, [456])
    end

    test "handles nil victim" do
      # Create custom killmail for this edge case with nil victim
      killmail = %{
        "victim" => nil,
        "attackers" => [
          %{"character_id" => 123}
        ]
      }

      assert CharacterMatcher.killmail_has_characters?(killmail, [123])
    end

    test "handles missing attackers" do
      # Create custom killmail for this edge case without attackers key
      killmail = %{
        "victim" => %{"character_id" => 123}
      }

      assert CharacterMatcher.killmail_has_characters?(killmail, [123])
      refute CharacterMatcher.killmail_has_characters?(killmail, [456])
    end

    test "handles atom keys in killmail" do
      killmail = %{
        victim: %{character_id: 123},
        attackers: [
          %{character_id: 456}
        ]
      }

      assert CharacterMatcher.killmail_has_characters?(killmail, [123])
      assert CharacterMatcher.killmail_has_characters?(killmail, [456])
    end

    test "handles mixed string and atom keys" do
      killmail = %{
        "victim" => %{character_id: 123},
        attackers: [
          %{"character_id" => 456}
        ]
      }

      assert CharacterMatcher.killmail_has_characters?(killmail, [123])
      assert CharacterMatcher.killmail_has_characters?(killmail, [456])
    end

    test "performs well with large attacker lists" do
      # Create a killmail with 1000 attackers
      attackers =
        Enum.map(1..1000, fn i ->
          %{"character_id" => i}
        end)

      killmail = %{
        "victim" => %{"character_id" => 9999},
        "attackers" => attackers
      }

      # Should find match quickly when character is early in the list
      assert CharacterMatcher.killmail_has_characters?(killmail, [5])

      # Should handle checking against the last attacker
      assert CharacterMatcher.killmail_has_characters?(killmail, [1000])

      # Should handle no matches efficiently
      refute CharacterMatcher.killmail_has_characters?(killmail, [9998])
    end
  end

  describe "extract_character_ids/1" do
    test "extracts victim and attacker character IDs" do
      killmail = build_killmail(123, [456, 789])

      assert CharacterMatcher.extract_character_ids(killmail) == [123, 456, 789]
    end

    test "removes duplicate character IDs" do
      killmail = build_killmail(123, [456, 123, 456])

      assert CharacterMatcher.extract_character_ids(killmail) == [123, 456]
    end

    test "handles missing victim character_id" do
      killmail = build_killmail(nil, [456, 789])

      assert CharacterMatcher.extract_character_ids(killmail) == [456, 789]
    end

    test "handles missing attacker character_ids" do
      killmail = %{
        "victim" => %{"character_id" => 123},
        "attackers" => [
          %{},
          %{"character_id" => 456},
          %{}
        ]
      }

      assert CharacterMatcher.extract_character_ids(killmail) == [123, 456]
    end

    test "handles empty attackers list" do
      killmail = %{
        "victim" => %{"character_id" => 123},
        "attackers" => []
      }

      assert CharacterMatcher.extract_character_ids(killmail) == [123]
    end

    test "handles missing attackers" do
      killmail = %{
        "victim" => %{"character_id" => 123}
      }

      assert CharacterMatcher.extract_character_ids(killmail) == [123]
    end

    test "handles nil victim" do
      killmail = %{
        "victim" => nil,
        "attackers" => [
          %{"character_id" => 456}
        ]
      }

      assert CharacterMatcher.extract_character_ids(killmail) == [456]
    end

    test "returns empty list when no character IDs found" do
      killmail = %{
        "victim" => %{},
        "attackers" => [%{}, %{}]
      }

      assert CharacterMatcher.extract_character_ids(killmail) == []
    end

    test "handles atom keys" do
      killmail = %{
        victim: %{character_id: 123},
        attackers: [
          %{character_id: 456}
        ]
      }

      assert CharacterMatcher.extract_character_ids(killmail) == [123, 456]
    end

    test "returns sorted character IDs" do
      killmail = %{
        "victim" => %{"character_id" => 789},
        "attackers" => [
          %{"character_id" => 123},
          %{"character_id" => 456}
        ]
      }

      assert CharacterMatcher.extract_character_ids(killmail) == [123, 456, 789]
    end
  end
end
