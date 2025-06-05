defmodule WandererKills.Cache.KeyTest do
  use ExUnit.Case, async: true
  alias WandererKills.Cache.Key

  describe "cache keys" do
    test "killmail keys" do
      assert Key.killmail_key(123) == "wanderer_kills:killmails:123"
      assert Key.system_killmails_key(456) == "wanderer_kills:killmails:system:456"
      assert Key.character_killmails_key(789) == "wanderer_kills:killmails:character:789"
      assert Key.corporation_killmails_key(101) == "wanderer_kills:killmails:corporation:101"
      assert Key.alliance_killmails_key(102) == "wanderer_kills:killmails:alliance:102"
    end

    test "system keys" do
      assert Key.system_data_key(123) == "wanderer_kills:system:123:data"
      assert Key.system_info_key(456) == "wanderer_kills:system:456:info"
      assert Key.system_kill_count_key(789) == "wanderer_kills:killmails:system:789:kill_count"
      assert Key.system_fetch_ts_key(101) == "wanderer_kills:killmails:system:101:fetch_timestamp"
      assert Key.system_ttl_key(102) == "wanderer_kills:system:102:ttl"
    end

    test "character keys" do
      assert Key.character_info_key(123) == "wanderer_kills:character:123:info"
    end

    test "corporation keys" do
      assert Key.corporation_info_key(123) == "wanderer_kills:corporation:123:info"
    end

    test "alliance keys" do
      assert Key.alliance_info_key(123) == "wanderer_kills:alliance:123:info"
    end

    test "esi keys" do
      assert Key.type_info_key(123) == "wanderer_kills:esi:type:123"
      assert Key.group_info_key(456) == "wanderer_kills:esi:group:456"
      assert Key.esi_character_info_key(789) == "wanderer_kills:esi:character:789"
      assert Key.esi_corporation_info_key(101) == "wanderer_kills:esi:corporation:101"
      assert Key.esi_alliance_info_key(102) == "wanderer_kills:esi:alliance:102"
      assert Key.esi_killmail_key(456) == "wanderer_kills:esi:killmail:456"
      assert Key.esi_system_killmails_key(789) == "wanderer_kills:esi:system:789:killmails"
    end
  end

  describe "key generation" do
    test "generate creates properly formatted keys" do
      assert Key.generate(:killmails, ["killmail", "123"]) ==
               "wanderer_kills:killmails:killmail:123"

      assert Key.generate(:system, ["data", "456"]) == "wanderer_kills:system:data:456"
      assert Key.generate(:esi, ["type", "789"]) == "wanderer_kills:esi:type:789"
    end
  end

  describe "key validation" do
    test "validate_key checks key format" do
      assert Key.validate_key("wanderer_kills:killmails:killmail:123")
      assert Key.validate_key("wanderer_kills:system:data:456")
      assert Key.validate_key("wanderer_kills:esi:type:789")
      refute Key.validate_key("invalid:key:format")
      refute Key.validate_key("wrong_prefix:killmails:killmail:123")
    end
  end

  describe "TTL management" do
    test "get_ttl returns configured TTL" do
      assert is_integer(Key.get_ttl(:killmails))
      assert is_integer(Key.get_ttl(:system))
      assert is_integer(Key.get_ttl(:esi))
    end
  end
end
