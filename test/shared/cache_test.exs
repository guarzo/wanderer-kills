defmodule WandererKills.CacheTest do
  use WandererKills.TestCase

  alias WandererKills.Cache.ESI
  alias WandererKills.Cache.Systems
  alias WandererKills.TestHelpers

  setup do
    WandererKills.Test.CacheHelpers.clear_all_caches()
    :ok
  end

  describe "killmail operations" do
    test "can store and retrieve a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      assert :ok = ESI.put_killmail(123, killmail)
      assert {:ok, ^killmail} = ESI.get_killmail(123)
    end

    test "returns error for non-existent killmail" do
      assert {:error, %WandererKills.Core.Error{type: :not_found}} = ESI.get_killmail(999)
    end

    test "can delete a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      assert :ok = ESI.put_killmail(123, killmail)
      assert :ok = ESI.delete_killmail(123)
      assert {:error, %WandererKills.Core.Error{type: :not_found}} = ESI.get_killmail(123)
    end
  end

  describe "system operations" do
    test "can store and retrieve system killmails" do
      killmail1 = TestHelpers.create_test_killmail(123)
      killmail2 = TestHelpers.create_test_killmail(456)

      assert :ok = ESI.put_killmail(123, killmail1)
      assert :ok = ESI.put_killmail(456, killmail2)
      assert :ok = Systems.add_killmail(789, 123)
      assert :ok = Systems.add_killmail(789, 456)

      assert {:ok, killmail_ids} = Systems.get_killmails(789)
      assert Enum.sort(killmail_ids) == [123, 456]
    end

    test "returns empty list for system with no killmails" do
      assert {:ok, []} = Systems.get_killmails(999)
    end

    test "can manage system killmails" do
      killmail = TestHelpers.create_test_killmail(123)
      assert :ok = ESI.put_killmail(123, killmail)
      assert :ok = Systems.add_killmail(888, 123)
      assert {:ok, [123]} = Systems.get_killmails(888)

      # Test that we can get system killmails
      assert {:ok, [123]} = Systems.get_killmails(888)
    end
  end

  describe "kill count operations" do
    test "can increment and get system kill count" do
      assert {:ok, 1} = Systems.increment_kill_count(789)
      assert {:ok, 2} = Systems.increment_kill_count(789)
      assert {:ok, 2} = Systems.get_kill_count(789)
    end

    test "returns 0 for system with no kills" do
      assert {:ok, 0} = Systems.get_kill_count(999)
    end
  end

  describe "fetch timestamp operations" do
    test "can set and check system fetch timestamp" do
      timestamp = DateTime.utc_now()
      assert {:ok, :set} = Systems.set_fetch_timestamp(789, timestamp)
      assert {:ok, true} = Systems.recently_fetched?(789)
    end

    test "returns false for system with no fetch timestamp" do
      assert {:ok, false} = Systems.recently_fetched?(999)
    end
  end
end
