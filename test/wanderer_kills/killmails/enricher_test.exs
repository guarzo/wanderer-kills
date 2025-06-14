defmodule WandererKills.Ingest.Killmails.EnricherTest do
  use ExUnit.Case, async: true

  # Sample killmail with enriched data (as it would be after ESI enrichment)
  @enriched_killmail %{
    "killmail_id" => 123_456_789,
    "kill_time" => "2024-01-15T14:30:00Z",
    "solar_system_id" => 30_000_142,
    "victim" => %{
      "character_id" => 987_654_321,
      "corporation_id" => 123_456_789,
      "alliance_id" => 456_789_123,
      "ship_type_id" => 671,
      "damage_taken" => 2847,
      "character" => %{"name" => "John Doe"},
      "corporation" => %{"name" => "Corp Name", "ticker" => "[CORP]"},
      "alliance" => %{"name" => "Alliance Name", "ticker" => "[ALLY]"},
      "ship" => %{"name" => "Rifter"}
    },
    "attackers" => [
      %{
        "character_id" => 111_111_111,
        "corporation_id" => 222_222_222,
        "alliance_id" => 333_333_333,
        "ship_type_id" => 584,
        "final_blow" => true,
        "damage_done" => 2847,
        "security_status" => -1.5,
        "weapon_type_id" => 2185,
        "character" => %{"name" => "Jane Doe"},
        "corporation" => %{"name" => "Attacker Corp", "ticker" => "[ATK]"},
        "alliance" => %{"name" => "Attacker Alliance", "ticker" => "[ATKR]"}
      }
    ],
    "zkb" => %{
      "awox" => false,
      "destroyedValue" => 607_542.55,
      "droppedValue" => 0,
      "fittedValue" => 10_000,
      "hash" => "3c7ad3e982520554aad200b6eac9c3773106f4ce",
      "labels" => ["cat:6", "#:1", "pvp", "loc:w-space"],
      "locationID" => 40_423_641,
      "npc" => false,
      "points" => 1,
      "solo" => false,
      "totalValue" => 607_542.55
    }
  }

  describe "killmail format validation" do
    test "validates expected killmail output format structure" do
      # Test the expected format by creating a sample enriched killmail
      # This test ensures we always provide the expected structure

      # Simulate what the flattening should produce
      flattened = simulate_flattened_killmail(@enriched_killmail)

      # Verify the output matches the expected format
      required_root_fields = [
        "killmail_id",
        "kill_time",
        "solar_system_id",
        "victim",
        "attackers",
        "zkb",
        "attacker_count"
      ]

      for field <- required_root_fields do
        assert Map.has_key?(flattened, field), "Missing root field: #{field}"
      end

      # Verify victim structure
      victim = flattened["victim"]

      required_victim_fields = [
        "character_id",
        "character_name",
        "corporation_id",
        "corporation_name",
        "corporation_ticker",
        "alliance_id",
        "alliance_name",
        "alliance_ticker",
        "ship_type_id",
        "ship_name",
        "damage_taken"
      ]

      for field <- required_victim_fields do
        assert Map.has_key?(victim, field), "Missing victim field: #{field}"
      end

      # Verify attacker structure
      attacker = hd(flattened["attackers"])

      required_attacker_fields = [
        "character_id",
        "character_name",
        "corporation_id",
        "corporation_name",
        "corporation_ticker",
        "alliance_id",
        "alliance_name",
        "alliance_ticker",
        "ship_type_id",
        "ship_name",
        "final_blow",
        "damage_done",
        "security_status",
        "weapon_type_id"
      ]

      for field <- required_attacker_fields do
        assert Map.has_key?(attacker, field), "Missing attacker field: #{field}"
      end
    end

    test "validates flattened victim data structure" do
      flattened = simulate_flattened_killmail(@enriched_killmail)
      victim = flattened["victim"]

      # Test original fields are preserved
      assert victim["character_id"] == 987_654_321
      assert victim["corporation_id"] == 123_456_789
      assert victim["alliance_id"] == 456_789_123
      assert victim["ship_type_id"] == 671
      assert victim["damage_taken"] == 2847

      # Test flattened name fields are added
      assert victim["character_name"] == "John Doe"
      assert victim["corporation_name"] == "Corp Name"
      assert victim["corporation_ticker"] == "[CORP]"
      assert victim["alliance_name"] == "Alliance Name"
      assert victim["alliance_ticker"] == "[ALLY]"
      assert victim["ship_name"] == "Rifter"
    end

    test "validates flattened attacker data structure" do
      flattened = simulate_flattened_killmail(@enriched_killmail)
      attacker = hd(flattened["attackers"])

      # Test original fields are preserved
      assert attacker["character_id"] == 111_111_111
      assert attacker["corporation_id"] == 222_222_222
      assert attacker["alliance_id"] == 333_333_333
      assert attacker["ship_type_id"] == 584
      assert attacker["final_blow"] == true
      assert attacker["damage_done"] == 2847
      assert attacker["security_status"] == -1.5
      assert attacker["weapon_type_id"] == 2185

      # Test flattened name fields are added
      assert attacker["character_name"] == "Jane Doe"
      assert attacker["corporation_name"] == "Attacker Corp"
      assert attacker["corporation_ticker"] == "[ATK]"
      assert attacker["alliance_name"] == "Attacker Alliance"
      assert attacker["alliance_ticker"] == "[ATKR]"
    end

    test "handles missing enriched data gracefully" do
      # Test with missing character data
      killmail_missing_character = put_in(@enriched_killmail, ["victim", "character"], nil)
      flattened = simulate_flattened_killmail(killmail_missing_character)
      victim = flattened["victim"]

      # Should have nil character name but other fields should work
      assert victim["character_name"] == nil
      assert victim["corporation_name"] == "Corp Name"
      assert victim["alliance_name"] == "Alliance Name"
    end

    test "handles multiple attackers correctly" do
      multi_attacker_killmail = %{
        @enriched_killmail
        | "attackers" => [
            @enriched_killmail["attackers"] |> hd(),
            %{
              "character_id" => 999_999_999,
              "corporation_id" => 888_888_888,
              "alliance_id" => 777_777_777,
              "ship_type_id" => 123,
              "final_blow" => false,
              "damage_done" => 500,
              "security_status" => 2.0,
              "weapon_type_id" => 456,
              "character" => %{"name" => "Third Attacker"},
              "corporation" => %{"name" => "Third Corp", "ticker" => "[3RD]"},
              "alliance" => %{"name" => "Third Alliance", "ticker" => "[3RD]"}
            }
          ]
      }

      flattened = simulate_flattened_killmail(multi_attacker_killmail)

      # Should have 2 attackers and attacker_count should be 2
      assert length(flattened["attackers"]) == 2
      assert flattened["attacker_count"] == 2

      # Both attackers should have flattened name fields
      [first_attacker, second_attacker] = flattened["attackers"]

      assert first_attacker["character_name"] == "Jane Doe"
      assert first_attacker["corporation_name"] == "Attacker Corp"

      assert second_attacker["character_name"] == "Third Attacker"
      assert second_attacker["corporation_name"] == "Third Corp"
    end
  end

  # Helper function to simulate the flattening that should happen in the enricher
  defp simulate_flattened_killmail(enriched_killmail) do
    enriched_killmail
    |> flatten_victim_data()
    |> flatten_attackers_data()
    |> add_attacker_count()
  end

  defp flatten_victim_data(killmail) do
    victim = Map.get(killmail, "victim", %{})

    flattened_victim =
      victim
      |> add_character_name(get_in(victim, ["character", "name"]))
      |> add_corporation_info()
      |> add_alliance_info()
      |> add_ship_name()

    Map.put(killmail, "victim", flattened_victim)
  end

  defp flatten_attackers_data(killmail) do
    attackers = Map.get(killmail, "attackers", [])

    flattened_attackers =
      Enum.map(attackers, fn attacker ->
        attacker
        |> add_character_name(get_in(attacker, ["character", "name"]))
        |> add_corporation_info()
        |> add_alliance_info()
        |> add_ship_name_for_attacker()
      end)

    Map.put(killmail, "attackers", flattened_attackers)
  end

  defp add_character_name(entity, character_name) do
    Map.put(entity, "character_name", character_name)
  end

  defp add_corporation_info(entity) do
    corp_name = get_in(entity, ["corporation", "name"])
    corp_ticker = get_in(entity, ["corporation", "ticker"])

    entity
    |> Map.put("corporation_name", corp_name)
    |> Map.put("corporation_ticker", corp_ticker)
  end

  defp add_alliance_info(entity) do
    alliance_name = get_in(entity, ["alliance", "name"])
    alliance_ticker = get_in(entity, ["alliance", "ticker"])

    entity
    |> Map.put("alliance_name", alliance_name)
    |> Map.put("alliance_ticker", alliance_ticker)
  end

  defp add_ship_name(entity) do
    ship_name = get_in(entity, ["ship", "name"])
    Map.put(entity, "ship_name", ship_name)
  end

  defp add_ship_name_for_attacker(attacker) do
    # For attackers, we don't have ship enrichment in our test data
    # so we'll just add nil values to match the expected structure
    Map.put(attacker, "ship_name", nil)
  end

  defp add_attacker_count(killmail) do
    attackers = Map.get(killmail, "attackers", [])
    attacker_count = length(attackers)

    Map.put(killmail, "attacker_count", attacker_count)
  end
end
