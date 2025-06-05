defmodule WandererKills.CacheTest do
  use WandererKills.TestCase

  alias WandererKills.Cache
  alias WandererKills.TestHelpers

  setup do
    Cachex.clear(:killmails_cache_test)
    Cachex.clear(:system_cache_test)
    Cachex.clear(:esi_cache_test)
    :ok
  end

  describe "killmail operations" do
    test "can store and retrieve a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      assert {:ok, true} = Cache.set_killmail(123, killmail)
      assert {:ok, ^killmail} = Cache.get_killmail(123)
    end

    test "returns error for non-existent killmail" do
      assert {:ok, nil} = Cache.get_killmail(999)
    end

    test "can delete a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      assert {:ok, true} = Cache.set_killmail(123, killmail)
      assert {:ok, true} = Cache.delete_killmail(123)
      assert {:ok, nil} = Cache.get_killmail(123)
    end
  end

  describe "system operations" do
    test "can store and retrieve system killmails" do
      killmail1 = TestHelpers.create_test_killmail(123)
      killmail2 = TestHelpers.create_test_killmail(456)

      assert {:ok, true} = Cache.set_killmail(123, killmail1)
      assert {:ok, true} = Cache.set_killmail(456, killmail2)
      assert {:ok, true} = Cache.add_system_killmail(789, 123)
      assert {:ok, true} = Cache.add_system_killmail(789, 456)

      assert {:ok, [123, 456]} = Cache.get_system_killmails(789)
    end

    test "returns empty list for system with no killmails" do
      assert {:ok, []} = Cache.get_system_killmails(999)
    end

    test "can remove killmail from system" do
      killmail = TestHelpers.create_test_killmail(123)
      assert {:ok, true} = Cache.set_killmail(123, killmail)
      assert {:ok, true} = Cache.add_system_killmail(789, 123)
      assert {:ok, true} = Cache.remove_system_killmail(789, 123)
      assert {:ok, []} = Cache.get_system_killmails(789)
    end
  end

  describe "kill count operations" do
    test "can increment and get system kill count" do
      assert {:ok, true} = Cache.increment_system_kill_count(789)
      assert {:ok, true} = Cache.increment_system_kill_count(789)
      assert {:ok, 2} = Cache.get_system_kill_count(789)
    end

    test "returns 0 for system with no kills" do
      assert {:ok, 0} = Cache.get_system_kill_count(999)
    end
  end

  describe "fetch timestamp operations" do
    test "can set and get system fetch timestamp" do
      timestamp = DateTime.utc_now()
      assert {:ok, true} = Cache.set_system_fetch_timestamp(789, timestamp)
      assert {:ok, ^timestamp} = Cache.get_system_fetch_timestamp(789)
    end

    test "returns nil for system with no fetch timestamp" do
      assert {:ok, nil} = Cache.get_system_fetch_timestamp(999)
    end
  end
end
