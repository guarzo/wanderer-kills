defmodule WandererKills.Domain.JsonEncoderTest do
  use ExUnit.Case, async: true

  alias WandererKills.Domain.{Attacker, Killmail, Victim, ZkbMetadata}

  describe "Killmail JSON encoding" do
    test "encodes a complete killmail struct to JSON" do
      killmail = %Killmail{
        killmail_id: 123_456,
        kill_time: "2024-01-01T12:00:00Z",
        system_id: 30_000_142,
        moon_id: 40_000_001,
        war_id: nil,
        victim: %Victim{
          character_id: 95_465_499,
          corporation_id: 98_000_001,
          alliance_id: nil,
          ship_type_id: 670,
          damage_taken: 1000,
          position: nil,
          character_name: "Test Pilot",
          corporation_name: "Test Corp",
          corporation_ticker: "TEST",
          alliance_name: nil,
          alliance_ticker: nil,
          ship_name: "Capsule"
        },
        attackers: [
          %Attacker{
            character_id: 90_379_338,
            corporation_id: 98_000_002,
            alliance_id: 99_000_001,
            ship_type_id: 671,
            weapon_type_id: 2456,
            damage_done: 1000,
            final_blow: true,
            security_status: 5.0,
            character_name: "Attacker Pilot",
            corporation_name: "Attacker Corp",
            corporation_ticker: "ATTK",
            alliance_name: "Attacker Alliance",
            alliance_ticker: "ATKR",
            ship_name: "Pod"
          }
        ],
        zkb: %ZkbMetadata{
          location_id: 60_003_760,
          hash: "abc123",
          fitted_value: 1000.0,
          dropped_value: 0.0,
          destroyed_value: 1000.0,
          total_value: 1000.0,
          points: 1,
          npc: false,
          solo: true,
          awox: false,
          labels: ["solo", "lowsec"]
        },
        attacker_count: 1
      }

      json = Jason.encode!(killmail)
      decoded = Jason.decode!(json)

      # Verify structure
      assert decoded["killmail_id"] == 123_456
      assert decoded["kill_time"] == "2024-01-01T12:00:00Z"
      assert decoded["system_id"] == 30_000_142
      assert decoded["moon_id"] == 40_000_001
      # nil fields should be omitted
      assert is_nil(decoded["war_id"])

      # Verify victim
      assert decoded["victim"]["character_id"] == 95_465_499
      assert decoded["victim"]["character_name"] == "Test Pilot"
      assert decoded["victim"]["ship_type_id"] == 670

      # Verify attackers
      assert length(decoded["attackers"]) == 1
      attacker = hd(decoded["attackers"])
      assert attacker["character_id"] == 90_379_338
      assert attacker["final_blow"] == true
      assert attacker["damage_done"] == 1000

      # Verify zkb
      assert decoded["zkb"]["totalValue"] == 1000.0
      assert decoded["zkb"]["solo"] == true
      assert decoded["zkb"]["npc"] == false
    end

    test "encodes minimal killmail struct" do
      killmail = %Killmail{
        killmail_id: 123,
        kill_time: "2024-01-01T12:00:00Z",
        system_id: 30_000_142,
        moon_id: nil,
        war_id: nil,
        victim: %Victim{
          character_id: 123,
          corporation_id: nil,
          alliance_id: nil,
          ship_type_id: 670,
          damage_taken: 100,
          position: nil,
          character_name: nil,
          corporation_name: nil,
          corporation_ticker: nil,
          alliance_name: nil,
          alliance_ticker: nil,
          ship_name: nil
        },
        attackers: [],
        zkb: nil,
        attacker_count: 0
      }

      json = Jason.encode!(killmail)
      decoded = Jason.decode!(json)

      # Verify only required fields are present
      assert decoded["killmail_id"] == 123
      assert decoded["system_id"] == 30_000_142
      assert Map.has_key?(decoded, "victim")
      assert decoded["attackers"] == []

      # Verify nil fields are omitted
      refute Map.has_key?(decoded, "moon_id")
      refute Map.has_key?(decoded, "war_id")
      refute Map.has_key?(decoded, "zkb")
      refute Map.has_key?(decoded["victim"], "corporation_id")
      refute Map.has_key?(decoded["victim"], "character_name")
    end

    test "encodes list of killmails" do
      killmails = [
        %Killmail{
          killmail_id: 1,
          kill_time: "2024-01-01T12:00:00Z",
          system_id: 30_000_142,
          victim: %Victim{
            character_id: 100,
            ship_type_id: 670,
            damage_taken: 100
          },
          attackers: []
        },
        %Killmail{
          killmail_id: 2,
          kill_time: "2024-01-01T13:00:00Z",
          system_id: 30_000_143,
          victim: %Victim{
            character_id: 200,
            ship_type_id: 671,
            damage_taken: 200
          },
          attackers: []
        }
      ]

      json = Jason.encode!(killmails)
      decoded = Jason.decode!(json)

      assert length(decoded) == 2
      assert Enum.at(decoded, 0)["killmail_id"] == 1
      assert Enum.at(decoded, 1)["killmail_id"] == 2
    end
  end

  describe "ZkbMetadata JSON encoding" do
    test "encodes zkb metadata with camelCase fields" do
      zkb = %ZkbMetadata{
        location_id: 60_003_760,
        hash: "abc123",
        fitted_value: 5000.0,
        dropped_value: 2000.0,
        destroyed_value: 3000.0,
        total_value: 5000.0,
        points: 10,
        npc: false,
        solo: false,
        awox: true,
        labels: ["highsec", "ganked"]
      }

      json = Jason.encode!(zkb)
      decoded = Jason.decode!(json)

      # Verify camelCase field names
      assert decoded["locationID"] == 60_003_760
      assert decoded["totalValue"] == 5000.0
      assert decoded["fittedValue"] == 5000.0
      assert decoded["droppedValue"] == 2000.0
      assert decoded["destroyedValue"] == 3000.0
      assert decoded["points"] == 10
      assert decoded["solo"] == false
      assert decoded["awox"] == true
      assert decoded["labels"] == ["highsec", "ganked"]
    end
  end
end
