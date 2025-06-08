defmodule WandererKills.CacheTest do
  use WandererKills.TestCase

  alias WandererKills.Cache.Helper
  alias WandererKills.TestHelpers

  setup do
    WandererKills.TestHelpers.clear_all_caches()
    :ok
  end

  describe "killmail operations" do
    test "can store and retrieve a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      assert {:ok, true} = Helper.killmail_put(123, killmail)
      assert {:ok, ^killmail} = Helper.killmail_get(123)
    end

    test "returns error for non-existent killmail" do
      assert {:error, :not_found} = Helper.killmail_get(999)
    end

    test "can delete a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      assert {:ok, true} = Helper.killmail_put(123, killmail)
      assert {:ok, true} = Helper.killmail_delete(123)

      assert {:error, :not_found} = Helper.killmail_get(123)
    end
  end

  describe "system operations" do
    test "can store and retrieve system killmails" do
      killmail1 = TestHelpers.create_test_killmail(123)
      killmail2 = TestHelpers.create_test_killmail(456)

      assert {:ok, true} = Helper.killmail_put(123, killmail1)
      assert {:ok, true} = Helper.killmail_put(456, killmail2)
      assert {:ok, true} = Helper.system_add_killmail(789, 123)
      assert {:ok, true} = Helper.system_add_killmail(789, 456)
      assert {:ok, killmail_ids} = Helper.system_get_killmails(789)
      assert 123 in killmail_ids
      assert 456 in killmail_ids
    end

    test "returns empty list for system with no killmails" do
      assert {:ok, []} = Helper.system_get_killmails(999)
    end

    test "can manage system killmails" do
      killmail = TestHelpers.create_test_killmail(123)
      assert {:ok, true} = Helper.killmail_put(123, killmail)
      assert {:ok, true} = Helper.system_add_killmail(789, 123)
      assert {:ok, killmail_ids} = Helper.system_get_killmails(789)
      assert 123 in killmail_ids
      assert {:ok, killmail_ids} = Helper.system_get_killmails(789)
      assert 123 in killmail_ids
    end
  end

  describe "kill count operations" do
    test "can increment and get system kill count" do
      assert {:ok, 1} = Helper.system_increment_kill_count(789)
      assert {:ok, 2} = Helper.system_increment_kill_count(789)
      assert {:ok, 2} = Helper.system_get_kill_count(789)
    end

    test "returns 0 for system with no kills" do
      assert {:ok, 0} = Helper.system_get_kill_count(999)
    end
  end

  describe "fetch timestamp operations" do
    test "can set and check system fetch timestamp" do
      timestamp = DateTime.utc_now()
      assert {:ok, :set} = Helper.system_set_fetch_timestamp(789, timestamp)
      assert true = Helper.system_recently_fetched?(789)
    end

    test "returns false for system with no fetch timestamp" do
      refute Helper.system_recently_fetched?(999)
    end
  end
end
