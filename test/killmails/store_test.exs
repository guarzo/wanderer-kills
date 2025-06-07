defmodule WandererKills.Killmails.StoreTest do
  use WandererKills.TestCase

  alias WandererKills.Killmails.Store
  alias WandererKills.TestHelpers

  @system_id_1 30_000_142

  @test_killmail_1 %{
    "killmail_id" => 12_345,
    "solar_system_id" => @system_id_1,
    "victim" => %{"character_id" => 123},
    "attackers" => [],
    "zkb" => %{"totalValue" => 1000}
  }

  @test_killmail_2 %{
    "killmail_id" => 12_346,
    "solar_system_id" => @system_id_1,
    "victim" => %{"character_id" => 124},
    "attackers" => [],
    "zkb" => %{"totalValue" => 2000}
  }

  setup do
    WandererKills.TestHelpers.clear_all_caches()
    # Clear Store tables before each test
    Store.clear()
    :ok
  end

  describe "killmail operations" do
    test "can store and retrieve a killmail" do
      killmail = @test_killmail_1
      :ok = Store.put(12_345, @system_id_1, killmail)
      assert {:ok, ^killmail} = Store.get(12_345)
    end

    test "returns error for non-existent killmail" do
      assert :error = Store.get(999)
    end

    test "can delete a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      :ok = Store.put(123, @system_id_1, killmail)
      :ok = Store.delete(123)
      assert :error = Store.get(123)
    end
  end

  describe "system operations" do
    test "can store and retrieve system killmails" do
      killmail1 = Map.put(@test_killmail_1, "killmail_id", 123)
      killmail2 = Map.put(@test_killmail_2, "killmail_id", 456)

      assert :ok = Store.put(123, @system_id_1, killmail1)
      assert :ok = Store.put(456, @system_id_1, killmail2)

      killmails = Store.list_by_system(@system_id_1)
      killmail_ids = Enum.map(killmails, & &1["killmail_id"])
      assert Enum.sort(killmail_ids) == [123, 456]
    end

    test "returns empty list for system with no killmails" do
      killmails = Store.list_by_system(@system_id_1)
      assert killmails == []
    end

    test "can remove killmail from system" do
      killmail = Map.put(@test_killmail_1, "killmail_id", 123)
      assert :ok = Store.put(123, @system_id_1, killmail)
      assert :ok = Store.delete(123)

      killmails = Store.list_by_system(@system_id_1)
      assert killmails == []
    end
  end

  describe "edge cases" do
    test "handles non-existent system" do
      non_existent_system = 99_999_999

      # Fetch for non-existent system should return empty list
      killmails = Store.list_by_system(non_existent_system)
      assert killmails == []
    end

    test "handles multiple systems correctly" do
      system_2 = 30_000_143

      killmail1 = Map.put(@test_killmail_1, "killmail_id", 123)
      killmail2 = Map.put(@test_killmail_2, "killmail_id", 456)

      # Store killmails in different systems
      assert :ok = Store.put(123, @system_id_1, killmail1)
      assert :ok = Store.put(456, system_2, killmail2)

      # Each system should only return its own killmails
      system_1_killmails = Store.list_by_system(@system_id_1)
      system_2_killmails = Store.list_by_system(system_2)

      assert length(system_1_killmails) == 1
      assert length(system_2_killmails) == 1
      assert hd(system_1_killmails)["killmail_id"] == 123
      assert hd(system_2_killmails)["killmail_id"] == 456
    end

    test "handles killmail updates correctly" do
      killmail = @test_killmail_1
      updated_killmail = Map.put(killmail, "updated", true)

      # Store initial killmail
      assert :ok = Store.put(12_345, @system_id_1, killmail)
      assert {:ok, ^killmail} = Store.get(12_345)

      # Update with new data
      assert :ok = Store.put(12_345, @system_id_1, updated_killmail)
      assert {:ok, ^updated_killmail} = Store.get(12_345)
    end
  end
end
