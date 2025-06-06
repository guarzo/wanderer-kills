defmodule WandererKills.CacheTest do
  use WandererKills.TestCase

  alias WandererKills.Cache
  alias WandererKills.TestHelpers

  setup do
    TestHelpers.clear_test_caches()
    :ok
  end

  describe "killmail operations" do
    test "can store and retrieve a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      assert :ok = Cache.set_killmail(123, killmail)
      assert {:ok, ^killmail} = Cache.get_killmail(123)
    end

    test "returns error for non-existent killmail" do
      assert {:error, :not_found} = Cache.get_killmail(999)
    end

    test "can delete a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      assert :ok = Cache.set_killmail(123, killmail)
      assert :ok = Cache.delete_killmail(123)
      assert {:error, :not_found} = Cache.get_killmail(123)
    end
  end

  describe "system operations" do
    test "can store and retrieve system killmails" do
      killmail1 = TestHelpers.create_test_killmail(123)
      killmail2 = TestHelpers.create_test_killmail(456)

      assert :ok = Cache.set_killmail(123, killmail1)
      assert :ok = Cache.set_killmail(456, killmail2)
      assert :ok = Cache.add_system_killmail(789, 123)
      assert :ok = Cache.add_system_killmail(789, 456)

      assert {:ok, killmail_ids} = Cache.get_killmails_for_system(789)
      assert Enum.sort(killmail_ids) == [123, 456]
    end

    test "returns empty list for system with no killmails" do
      assert {:ok, []} = Cache.get_killmails_for_system(999)
    end

    test "can manage system killmails" do
      killmail = TestHelpers.create_test_killmail(123)
      assert :ok = Cache.set_killmail(123, killmail)
      assert :ok = Cache.add_system_killmail(789, 123)
      assert {:ok, [123]} = Cache.get_killmails_for_system(789)

      # Test that we can get system killmails
      assert {:ok, [123]} = Cache.get_system_killmails(789)
    end
  end

  describe "kill count operations" do
    test "can increment and get system kill count" do
      assert :ok = Cache.increment_system_kill_count(789)
      assert :ok = Cache.increment_system_kill_count(789)
      assert {:ok, 2} = Cache.get_system_kill_count(789)
    end

    test "returns 0 for system with no kills" do
      assert {:ok, 0} = Cache.get_system_kill_count(999)
    end
  end

  describe "fetch timestamp operations" do
    test "can set and check system fetch timestamp" do
      timestamp = DateTime.utc_now()
      assert :ok = Cache.set_system_fetch_timestamp(789, timestamp)
      assert {:ok, true} = Cache.system_recently_fetched?(789)
    end

    test "returns false for system with no fetch timestamp" do
      assert {:ok, false} = Cache.system_recently_fetched?(999)
    end
  end
end
