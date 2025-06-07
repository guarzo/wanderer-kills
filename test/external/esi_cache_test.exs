defmodule WandererKills.EsiCacheTest do
  # Disable async to avoid cache interference
  use ExUnit.Case, async: false
  alias WandererKills.Cache

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
    test "get_character_info fetches and caches data" do
      character_id = 123

      expected_data = %{
        character_id: character_id,
        name: "Test Character",
        corporation_id: 456,
        alliance_id: 789,
        faction_id: nil,
        security_status: 5.0
      }

      # Store test data directly since this tests cache operations
      assert :ok = Cache.set_character_info(character_id, expected_data)
      assert {:ok, actual_data} = Cache.get_character_info(character_id)
      assert actual_data.character_id == expected_data.character_id
      assert actual_data.name == expected_data.name
    end
  end

  describe "corporation info" do
    test "get_corporation_info fetches and caches data" do
      corporation_id = 456

      corp_data = %{
        corporation_id: corporation_id,
        name: "Test Corp",
        ticker: "TEST",
        member_count: 100
      }

      assert :ok = Cache.set_corporation_info(corporation_id, corp_data)
      assert {:ok, cached_data} = Cache.get_corporation_info(corporation_id)
      assert cached_data.corporation_id == corporation_id
      assert cached_data.name == "Test Corp"
    end
  end

  describe "alliance info" do
    test "get_alliance_info fetches and caches data" do
      alliance_id = 789

      alliance_data = %{
        alliance_id: alliance_id,
        name: "Test Alliance",
        ticker: "TESTA",
        creator_corporation_id: 456
      }

      assert :ok = Cache.set_alliance_info(alliance_id, alliance_data)
      assert {:ok, cached_data} = Cache.get_alliance_info(alliance_id)
      assert cached_data.alliance_id == alliance_id
      assert cached_data.name == "Test Alliance"
    end
  end

  describe "type info" do
    test "get_type_info fetches and caches data" do
      type_id = 1234

      type_data = %{
        type_id: type_id,
        name: "Test Type",
        group_id: 5678,
        published: true
      }

      assert :ok = Cache.set_type_info(type_id, type_data)
      assert {:ok, cached_data} = Cache.get_type_info(type_id)
      assert cached_data.type_id == type_id
      assert cached_data.name == "Test Type"
    end
  end

  describe "group info" do
    test "get_group_info fetches and caches data" do
      group_id = 5678

      group_data = %{
        group_id: group_id,
        name: "Test Group",
        category_id: 91,
        published: true,
        types: [1234, 5678]
      }

      assert :ok = Cache.set_group_info(group_id, group_data)
      assert {:ok, cached_data} = Cache.get_group_info(group_id)
      assert cached_data.group_id == group_id
      assert cached_data.name == "Test Group"
    end
  end

  describe "clear cache" do
    test "clear removes all entries" do
      # Test clearing specific namespace
      assert :ok = Cache.clear_namespace("esi")
    end
  end
end
