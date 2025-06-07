defmodule WandererKills.Killmails.StoreTest do
  use WandererKills.TestCase

  alias WandererKills.KillStore
  alias WandererKills.TestHelpers

  @system_id_1 30_000_142
  @system_id_2 30_000_143

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

  @test_killmail_3 %{
    "killmail_id" => 12_347,
    "solar_system_id" => @system_id_2,
    "victim" => %{"character_id" => 125},
    "attackers" => [],
    "zkb" => %{"totalValue" => 3000}
  }

  setup do
    WandererKills.TestHelpers.clear_all_caches()
    # Clear KillStore tables before each test
    KillStore.clear_all()
    :ok
  end

  describe "killmail operations" do
    test "can store and retrieve a killmail" do
      killmail = @test_killmail_1
      :ok = KillStore.put(12_345, killmail)
      assert {:ok, ^killmail} = KillStore.get(12_345)
    end

    test "returns error for non-existent killmail" do
      assert {:error, :not_found} = KillStore.get(999)
    end

    test "can delete a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      :ok = KillStore.put(123, killmail)
      :ok = KillStore.delete(123)
      assert {:error, :not_found} = KillStore.get(123)
    end
  end

  describe "system operations" do
    test "can store and retrieve system killmails" do
      killmail1 = Map.put(@test_killmail_1, "killmail_id", 123)
      killmail2 = Map.put(@test_killmail_1, "killmail_id", 456)

      assert :ok = KillStore.put(123, killmail1)
      assert :ok = KillStore.put(456, killmail2)

      killmails = KillStore.list_by_system(30_000_142)
      killmail_ids = Enum.map(killmails, & &1["killmail_id"])
      assert Enum.sort(killmail_ids) == [123, 456]
    end

    test "returns empty list for system with no killmails" do
      killmails = KillStore.list_by_system(30_000_142)
      assert killmails == []
    end

    test "can remove killmail from system" do
      killmail = Map.put(@test_killmail_1, "killmail_id", 123)
      assert :ok = KillStore.put(123, killmail)
      assert :ok = KillStore.delete(123)

      killmails = KillStore.list_by_system(30_000_142)
      assert killmails == []
    end
  end

  # Note: Kill count and fetch timestamp operations are now handled by the Cache.Systems module
  # The simplified KillStore focuses only on basic killmail storage and retrieval

  describe "basic functionality" do
    test "can insert and fetch events for a client" do
      assert :ok = KillStore.insert_event(@system_id_1, @test_killmail_1)
      assert :ok = KillStore.insert_event(@system_id_1, @test_killmail_2)

      events = KillStore.fetch_events("client1", [@system_id_1])
      assert length(events) == 2

      # Verify events contain the killmail data
      killmail_ids = Enum.map(events, & &1["killmail_id"])
      assert 12_345 in killmail_ids
      assert 12_346 in killmail_ids
    end
  end

  describe "offset tracking" do
    test "client offsets can be managed" do
      assert :ok = KillStore.insert_event(@system_id_1, @test_killmail_1)
      assert :ok = KillStore.insert_event(@system_id_1, @test_killmail_2)

      # Get initial events
      events_1 = KillStore.fetch_events("client1", [@system_id_1])
      assert length(events_1) == 2

      # Test offset management
      offsets = %{@system_id_1 => 1}
      assert :ok = KillStore.put_client_offsets("client1", offsets)

      retrieved_offsets = KillStore.get_client_offsets("client1")
      assert retrieved_offsets[@system_id_1] == 1
    end

    test "client offsets are independent" do
      offsets_1 = %{@system_id_1 => 5}
      offsets_2 = %{@system_id_1 => 10}

      assert :ok = KillStore.put_client_offsets("client1", offsets_1)
      assert :ok = KillStore.put_client_offsets("client2", offsets_2)

      assert KillStore.get_client_offsets("client1")[@system_id_1] == 5
      assert KillStore.get_client_offsets("client2")[@system_id_1] == 10
    end
  end

  describe "edge cases" do
    test "handles empty system list" do
      # Insert events
      assert :ok = KillStore.insert_event(@system_id_1, @test_killmail_1)

      # Fetch with empty system list
      events = KillStore.fetch_events("client1", [])
      assert events == []
    end

    test "handles non-existent client" do
      assert :ok = KillStore.insert_event(@system_id_1, @test_killmail_1)

      events = KillStore.fetch_events("new_client", [@system_id_1])
      # Should return events regardless of client (no pre-existing offsets)
      assert length(events) == 1
    end

    test "handles non-existent system" do
      non_existent_system = 99_999_999

      # Insert events for existing system
      assert :ok = KillStore.insert_event(@system_id_1, @test_killmail_1)

      # Fetch for non-existent system
      events = KillStore.fetch_events("client1", [non_existent_system])
      assert events == []
    end
  end
end
