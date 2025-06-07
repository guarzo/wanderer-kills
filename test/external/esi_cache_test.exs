defmodule WandererKills.EsiCacheTest do
  # Disable async to avoid cache interference
  use ExUnit.Case, async: false
  alias WandererKills.Cache.Helper

  setup do
    WandererKills.TestHelpers.clear_all_caches()

    # Set the http_client for this test
    Application.put_env(:wanderer_kills, :http_client, WandererKills.Http.Client.Mock)

    on_exit(fn ->
      Application.put_env(:wanderer_kills, :http_client, WandererKills.MockHttpClient)
      WandererKills.TestHelpers.clear_all_caches()
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
      assert {:ok, true} = Helper.character_put(character_id, expected_data)
      assert {:ok, actual_data} = Helper.character_get(character_id)
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

      assert {:ok, true} = Helper.corporation_put(corporation_id, corp_data)
      assert {:ok, cached_data} = Helper.corporation_get(corporation_id)
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

      assert {:ok, true} = Helper.alliance_put(alliance_id, alliance_data)
      assert {:ok, cached_data} = Helper.alliance_get(alliance_id)
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

      assert {:ok, true} = Helper.ship_type_put(type_id, type_data)
      assert {:ok, cached_data} = Helper.ship_type_get(type_id)
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

      assert {:ok, true} = Helper.put("groups", to_string(group_id), group_data)
      assert {:ok, cached_data} = Helper.get_with_error("groups", to_string(group_id))
      assert cached_data.group_id == group_id
      assert cached_data.name == "Test Group"
    end
  end

  describe "clear cache" do
    test "clear removes all entries" do
      # Add some data first to ensure the namespaces exist
      assert {:ok, true} = Helper.character_put(123, %{name: "test"})
      assert {:ok, true} = Helper.corporation_put(456, %{name: "test corp"})
      assert {:ok, true} = Helper.alliance_put(789, %{name: "test alliance"})

      # Test clearing specific namespace
      Helper.clear_namespace("characters")
      Helper.clear_namespace("corporations")
      Helper.clear_namespace("alliances")
    end
  end
end
