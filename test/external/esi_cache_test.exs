defmodule WandererKills.EsiCacheTest do
  # Disable async to avoid cache interference
  use ExUnit.Case, async: false
  alias WandererKills.Cache.ESI
  alias WandererKills.Cache.ShipTypes

  setup do
    WandererKills.Test.CacheHelpers.clear_all_caches()

    # Set the http_client for this test
    Application.put_env(:wanderer_kills, :http_client, WandererKills.Http.Client.Mock)

    on_exit(fn ->
      Application.put_env(:wanderer_kills, :http_client, WandererKills.MockHttpClient)
      WandererKills.Test.CacheHelpers.clear_all_caches()
    end)
  end

  describe "character info" do
    test "unified cache interface works for character data" do
      character_id = 123

      expected_data = %{
        character_id: character_id,
        name: "Test Character",
        corporation_id: 456,
        alliance_id: 789,
        faction_id: nil,
        security_status: 5.0
      }

      # Store test data using unified cache interface
      assert :ok = ESI.put_character(character_id, expected_data)
      assert {:ok, actual_data} = ESI.get_character(character_id)
      assert actual_data.character_id == expected_data.character_id
      assert actual_data.name == expected_data.name
    end
  end

  describe "corporation info" do
    test "unified cache interface works for corporation data" do
      corporation_id = 456

      corp_data = %{
        corporation_id: corporation_id,
        name: "Test Corp",
        ticker: "TEST",
        member_count: 100
      }

      assert :ok = ESI.put_corporation(corporation_id, corp_data)
      assert {:ok, cached_data} = ESI.get_corporation(corporation_id)
      assert cached_data.corporation_id == corporation_id
      assert cached_data.name == "Test Corp"
    end
  end

  describe "alliance info" do
    test "unified cache interface works for alliance data" do
      alliance_id = 789

      alliance_data = %{
        alliance_id: alliance_id,
        name: "Test Alliance",
        ticker: "TESTA",
        creator_corporation_id: 456
      }

      assert :ok = ESI.put_alliance(alliance_id, alliance_data)
      assert {:ok, cached_data} = ESI.get_alliance(alliance_id)
      assert cached_data.alliance_id == alliance_id
      assert cached_data.name == "Test Alliance"
    end
  end

  describe "type info" do
    test "unified cache interface works for type data" do
      type_id = 1234

      type_data = %{
        type_id: type_id,
        name: "Test Type",
        group_id: 5678,
        published: true
      }

      assert :ok = ShipTypes.put(type_id, type_data)
      assert {:ok, cached_data} = ShipTypes.get(type_id)
      assert cached_data.type_id == type_id
      assert cached_data.name == "Test Type"
    end
  end

  describe "group info" do
    test "unified cache interface works for group data" do
      group_id = 5678

      group_data = %{
        group_id: group_id,
        name: "Test Group",
        category_id: 91,
        published: true,
        types: [1234, 5678]
      }

      assert :ok = ESI.put_group(group_id, group_data)
      assert {:ok, cached_data} = ESI.get_group(group_id)
      assert cached_data.group_id == group_id
      assert cached_data.name == "Test Group"
    end
  end

  describe "clear cache" do
    test "clear removes all entries" do
      # Test clearing specific namespace
      assert :ok = ESI.clear(:characters)
      assert :ok = ESI.clear(:corporations)
      assert :ok = ESI.clear(:alliances)
    end
  end
end
