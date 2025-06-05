defmodule WandererKills.KillmailStoreTest do
  use WandererKills.TestCase

  alias WandererKills.KillmailStore
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
    # Clean up ETS tables before each test
    KillmailStore.cleanup_tables()
    :ok
  end

  describe "killmail operations" do
    test "can store and retrieve a killmail" do
      killmail = @test_killmail_1
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)
      assert {:ok, ^killmail} = KillmailStore.get_killmail(12_345)
    end

    test "returns error for non-existent killmail" do
      assert {:error, :not_found} = KillmailStore.get_killmail(999)
    end

    test "can delete a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      assert :ok = KillmailStore.store_killmail(killmail)
      assert :ok = KillmailStore.delete_killmail(123)
      assert {:error, :not_found} = KillmailStore.get_killmail(123)
    end
  end

  describe "system operations" do
    test "can store and retrieve system killmails" do
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_2)
      Process.sleep(10)
      assert :ok = KillmailStore.add_system_killmail(30_000_142, 123)
      assert :ok = KillmailStore.add_system_killmail(30_000_142, 456)
      assert {:ok, [123, 456]} = KillmailStore.get_system_killmails(30_000_142)
    end

    test "returns empty list for system with no killmails" do
      assert {:ok, []} = KillmailStore.get_system_killmails(30_000_142)
    end

    test "can remove killmail from system" do
      _killmail = TestHelpers.create_test_killmail(123)
      assert :ok = KillmailStore.add_system_killmail(30_000_142, 123)
      assert :ok = KillmailStore.remove_system_killmail(30_000_142, 123)
      assert {:ok, []} = KillmailStore.get_system_killmails(30_000_142)
    end
  end

  describe "kill count operations" do
    test "can increment and get system kill count" do
      assert :ok = KillmailStore.increment_system_kill_count(30_000_142)
      assert :ok = KillmailStore.increment_system_kill_count(30_000_142)
      assert {:ok, 2} = KillmailStore.get_system_kill_count(30_000_142)
    end

    test "returns 0 for system with no kills" do
      assert {:ok, 0} = KillmailStore.get_system_kill_count(30_000_142)
    end
  end

  describe "fetch timestamp operations" do
    test "can set and get system fetch timestamp" do
      timestamp = DateTime.utc_now()
      assert :ok = KillmailStore.set_system_fetch_timestamp(30_000_142, timestamp)
      assert {:ok, ^timestamp} = KillmailStore.get_system_fetch_timestamp(30_000_142)
    end

    test "returns error for system with no fetch timestamp" do
      assert {:error, :not_found} = KillmailStore.get_system_fetch_timestamp(30_000_142)
    end
  end

  describe "basic functionality" do
    test "can insert and fetch events for a client" do
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_2)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_3)
      Process.sleep(10)
      {:ok, events} = KillmailStore.fetch_for_client("client1", [@system_id_1])
      assert length(events) == 3

      event_ids = Enum.map(events, &elem(&1, 0))
      assert event_ids == Enum.sort(event_ids)
      assert Enum.all?(event_ids, &(&1 > 0))

      # Verify event structure
      [{event_id_1, sys_id_1, km_1}, {event_id_2, sys_id_2, km_2}, {event_id_3, sys_id_3, km_3}] =
        events

      assert sys_id_1 == @system_id_1
      assert sys_id_2 == @system_id_1
      assert sys_id_3 == @system_id_1

      assert km_1["killmail_id"] == 12_345
      assert km_2["killmail_id"] == 12_346
      assert km_3["killmail_id"] == 12_347

      assert event_id_1 < event_id_2
      assert event_id_2 < event_id_3
    end

    test "events are broadcast via PubSub" do
      # Subscribe to system topic
      Phoenix.PubSub.subscribe(WandererKills.PubSub, "system:#{@system_id_1}")

      # Insert an event
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)

      # Should receive PubSub message
      assert_receive {:new_killmail, @system_id_1, killmail}
      assert killmail["killmail_id"] == 12_345
    end
  end

  describe "offset tracking" do
    test "client offsets prevent duplicate fetches" do
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_2)
      Process.sleep(10)
      {:ok, events_1} = KillmailStore.fetch_for_client("client1", [@system_id_1])
      assert length(events_1) == 2
      {:ok, events_2} = KillmailStore.fetch_for_client("client1", [@system_id_1])
      assert events_2 == []
    end

    test "fetch_one_event returns single event and updates offset" do
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)

      {:ok, {event_id_1, sys_id, killmail_1}} =
        KillmailStore.fetch_one_event("client1", [@system_id_1])

      assert event_id_1 > 0
      assert sys_id == @system_id_1
      assert killmail_1 == @test_killmail_1
    end
  end

  describe "multi-client support" do
    test "different clients have independent offsets" do
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_2)
      Process.sleep(10)
      {:ok, events_1} = KillmailStore.fetch_for_client("client1", [@system_id_1])
      assert length(events_1) == 2
      {:ok, events_2} = KillmailStore.fetch_for_client("client2", [@system_id_1])
      assert length(events_2) == 2
    end

    test "clients can track different systems independently" do
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_2, @test_killmail_2)
      Process.sleep(10)
      {:ok, sys1_events} = KillmailStore.fetch_for_client("client1", [@system_id_1])
      assert length(sys1_events) == 1
      {:ok, sys2_events} = KillmailStore.fetch_for_client("client2", [@system_id_2])
      assert length(sys2_events) == 1
    end
  end

  describe "system filtering" do
    test "only returns events for requested systems" do
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_2)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_2, @test_killmail_3)
      Process.sleep(10)
      {:ok, sys1_events} = KillmailStore.fetch_for_client("client1", [@system_id_1])
      assert length(sys1_events) == 2
      {:ok, sys2_events} = KillmailStore.fetch_for_client("client1", [@system_id_2])
      assert length(sys2_events) == 1
    end
  end

  describe "edge cases" do
    test "handles empty system list" do
      client_id = "empty-systems-client"

      # Insert events
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)

      # Fetch with empty system list
      {:ok, events} = KillmailStore.fetch_for_client(client_id, [])
      assert events == []

      # fetch_one with empty system list
      assert :empty = KillmailStore.fetch_one_event(client_id, [])
    end

    test "handles non-existent client" do
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)
      {:ok, events} = KillmailStore.fetch_for_client("new_client", [@system_id_1])
      assert length(events) == 1
    end

    test "handles non-existent system" do
      client_id = "missing-system-client"
      non_existent_system = 99_999_999

      # Insert events for existing system
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)

      # Fetch for non-existent system
      {:ok, events} = KillmailStore.fetch_for_client(client_id, [non_existent_system])
      assert events == []

      # fetch_one for non-existent system
      assert :empty = KillmailStore.fetch_one_event(client_id, [non_existent_system])
    end
  end

  describe "event ordering" do
    test "events are returned in chronological order" do
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_2)
      Process.sleep(10)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_3)
      Process.sleep(10)
      {:ok, events} = KillmailStore.fetch_for_client("client1", [@system_id_1])
      assert length(events) == 3
      [event1, event2, event3] = events
      assert event1 < event2
      assert event2 < event3
    end
  end
end
