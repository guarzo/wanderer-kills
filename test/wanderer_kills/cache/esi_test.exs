defmodule WandererKills.Cache.Specialized.EsiCacheTest do
  use ExUnit.Case, async: true
  alias WandererKills.Cache.Specialized.EsiCache
  alias WandererKills.Esi.Data.Types.CharacterInfo

  setup do
    WandererKills.TestHelpers.clear_all_caches()

    # Set the http_client for this test
    Application.put_env(:wanderer_kills, :http_client, WandererKills.Http.Client.Mock)

    on_exit(fn ->
      Application.put_env(:wanderer_kills, :http_client, WandererKills.MockHttpClient)
    end)
  end

  describe "character info" do
    test "get_character_info fetches and caches data" do
      character_id = 123

      expected_data = %CharacterInfo{
        character_id: character_id,
        name: "Test Character",
        corporation_id: 456,
        alliance_id: 789,
        faction_id: nil,
        security_status: 5.0
      }

      # Mock the HTTP client to return expected data
      Mox.expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn _url, _opts ->
        {:ok,
         %{
           body: %{
             "name" => "Test Character",
             "corporation_id" => 456,
             "alliance_id" => 789,
             "faction_id" => nil,
             "security_status" => 5.0
           }
         }}
      end)

      assert {:ok, actual_data} = EsiCache.get_character_info(character_id)
      assert actual_data.character_id == expected_data.character_id
      assert actual_data.name == expected_data.name
    end
  end

  describe "corporation info" do
    test "get_corporation_info fetches and caches data" do
      corporation_id = 456

      Mox.expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn _url, _opts ->
        {:ok,
         %{
           body: %{
             "name" => "Test Corp",
             "ticker" => "TEST",
             "member_count" => 100
           }
         }}
      end)

      assert {:ok, corp_data} = EsiCache.get_corporation_info(corporation_id)
      assert corp_data.corporation_id == corporation_id
      assert corp_data.name == "Test Corp"
    end
  end

  describe "alliance info" do
    test "get_alliance_info fetches and caches data" do
      alliance_id = 789

      Mox.expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn _url, _opts ->
        {:ok,
         %{
           body: %{
             "name" => "Test Alliance",
             "ticker" => "TESTA",
             "creator_corporation_id" => 456
           }
         }}
      end)

      assert {:ok, alliance_data} = EsiCache.get_alliance_info(alliance_id)
      assert alliance_data.alliance_id == alliance_id
      assert alliance_data.name == "Test Alliance"
    end
  end

  describe "type info" do
    test "get_type_info fetches and caches data" do
      type_id = 1234

      Mox.expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn _url, _opts ->
        {:ok,
         %{
           body: %{
             "name" => "Test Type",
             "group_id" => 5678,
             "published" => true
           }
         }}
      end)

      assert {:ok, type_data} = EsiCache.get_type_info(type_id)
      assert type_data.type_id == type_id
      assert type_data.name == "Test Type"
    end
  end

  describe "group info" do
    test "get_group_info fetches and caches data" do
      group_id = 5678

      Mox.expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn _url, _opts ->
        {:ok,
         %{
           body: %{
             "name" => "Test Group",
             "category_id" => 91,
             "published" => true,
             "types" => [1234, 5678]
           }
         }}
      end)

      assert {:ok, group_data} = EsiCache.get_group_info(group_id)
      assert group_data.group_id == group_id
      assert group_data.name == "Test Group"
    end
  end

  describe "clear cache" do
    test "clear removes all entries" do
      assert :ok = EsiCache.clear()
    end
  end
end
