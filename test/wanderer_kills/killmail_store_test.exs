defmodule WandererKills.KillmailStoreTest do
  use ExUnit.Case, async: true

  alias WandererKills.KillmailStore

  @system_id_1 30_000_142
  @system_id_2 30_000_143

  @test_killmail_1 %{
    "killmail_id" => 12345,
    "solar_system_id" => @system_id_1,
    "victim" => %{"character_id" => 123},
    "attackers" => [],
    "zkb" => %{"totalValue" => 1000}
  }

  @test_killmail_2 %{
    "killmail_id" => 12346,
    "solar_system_id" => @system_id_1,
    "victim" => %{"character_id" => 124},
    "attackers" => [],
    "zkb" => %{"totalValue" => 2000}
  }

  @test_killmail_3 %{
    "killmail_id" => 12347,
    "solar_system_id" => @system_id_2,
    "victim" => %{"character_id" => 125},
    "attackers" => [],
    "zkb" => %{"totalValue" => 3000}
  }

  setup do
    # Start PubSub for testing
    start_supervised!({Phoenix.PubSub, name: WandererKills.PubSub})

    # Start KillmailStore
    start_supervised!(WandererKills.KillmailStore)

    :ok
  end

  describe "basic functionality" do
    test "can insert and fetch events for a client" do
      client_id = "test-client-1"

      # Insert three events for the same system
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_2)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_3)

      # Fetch events for the client
      {:ok, events} = KillmailStore.fetch_for_client(client_id, [@system_id_1])

      # Should get all three events with increasing event_ids
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

      assert km_1["killmail_id"] == 12345
      assert km_2["killmail_id"] == 12346
      assert km_3["killmail_id"] == 12347

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
      assert killmail["killmail_id"] == 12345
    end
  end

  describe "offset tracking" do
    test "client offsets prevent duplicate fetches" do
      client_id = "test-client-2"

      # Insert events
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_2)

      # First fetch should return all events
      {:ok, events_1} = KillmailStore.fetch_for_client(client_id, [@system_id_1])
      assert length(events_1) == 2

      # Second fetch should return empty list (offsets updated)
      {:ok, events_2} = KillmailStore.fetch_for_client(client_id, [@system_id_1])
      assert events_2 == []

      # Insert another event
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_3)

      # Third fetch should return only the new event
      {:ok, events_3} = KillmailStore.fetch_for_client(client_id, [@system_id_1])
      assert length(events_3) == 1

      [{_event_id, _sys_id, killmail}] = events_3
      assert killmail["killmail_id"] == 12347
    end

    test "fetch_one_event returns single event and updates offset" do
      client_id = "test-client-3"

      # Insert events
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_2)

      # First fetch_one should return earliest event
      {:ok, {event_id_1, sys_id, killmail_1}} =
        KillmailStore.fetch_one_event(client_id, [@system_id_1])

      assert sys_id == @system_id_1
      assert killmail_1["killmail_id"] == 12345

      # Second fetch_one should return next event
      {:ok, {event_id_2, sys_id, killmail_2}} =
        KillmailStore.fetch_one_event(client_id, [@system_id_1])

      assert sys_id == @system_id_1
      assert killmail_2["killmail_id"] == 12346
      assert event_id_2 > event_id_1

      # Third fetch_one should return :empty
      assert :empty = KillmailStore.fetch_one_event(client_id, [@system_id_1])
    end
  end

  describe "multi-client support" do
    test "different clients have independent offsets" do
      client_1 = "client-1"
      client_2 = "client-2"

      # Insert events
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      :ok = KillmailStore.insert_event(@system_id_2, @test_killmail_2)

      # Client 1 fetches all events
      {:ok, events_1} = KillmailStore.fetch_for_client(client_1, [@system_id_1, @system_id_2])
      assert length(events_1) == 2

      # Client 2 should still get all events (independent offsets)
      {:ok, events_2} = KillmailStore.fetch_for_client(client_2, [@system_id_1, @system_id_2])
      assert length(events_2) == 2

      # Client 1 second fetch should be empty
      {:ok, events_1_again} =
        KillmailStore.fetch_for_client(client_1, [@system_id_1, @system_id_2])

      assert events_1_again == []

      # Client 2 second fetch should also be empty
      {:ok, events_2_again} =
        KillmailStore.fetch_for_client(client_2, [@system_id_1, @system_id_2])

      assert events_2_again == []
    end

    test "clients can track different systems independently" do
      client_id = "multi-system-client"

      # Insert events for different systems
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      :ok = KillmailStore.insert_event(@system_id_2, @test_killmail_2)

      # Fetch only system 1 events
      {:ok, sys1_events} = KillmailStore.fetch_for_client(client_id, [@system_id_1])
      assert length(sys1_events) == 1
      [{_, sys_id, _}] = sys1_events
      assert sys_id == @system_id_1

      # Fetch only system 2 events (should still work since different system)
      {:ok, sys2_events} = KillmailStore.fetch_for_client(client_id, [@system_id_2])
      assert length(sys2_events) == 1
      [{_, sys_id, _}] = sys2_events
      assert sys_id == @system_id_2

      # Both system fetches should now be empty
      {:ok, empty_1} = KillmailStore.fetch_for_client(client_id, [@system_id_1])
      {:ok, empty_2} = KillmailStore.fetch_for_client(client_id, [@system_id_2])
      assert empty_1 == []
      assert empty_2 == []
    end
  end

  describe "system filtering" do
    test "only returns events for requested systems" do
      client_id = "system-filter-client"

      # Insert events for multiple systems
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      :ok = KillmailStore.insert_event(@system_id_2, @test_killmail_2)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_3)

      # Fetch events only for system 1
      {:ok, sys1_events} = KillmailStore.fetch_for_client(client_id, [@system_id_1])
      assert length(sys1_events) == 2

      # All events should be for system 1
      Enum.each(sys1_events, fn {_event_id, sys_id, _killmail} ->
        assert sys_id == @system_id_1
      end)

      # Fetch events only for system 2
      {:ok, sys2_events} = KillmailStore.fetch_for_client(client_id, [@system_id_2])
      assert length(sys2_events) == 1

      [{_event_id, sys_id, _killmail}] = sys2_events
      assert sys_id == @system_id_2
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
      client_id = "new-client"

      # Insert events
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)

      # New client should get all existing events
      {:ok, events} = KillmailStore.fetch_for_client(client_id, [@system_id_1])
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
      client_id = "order-test-client"

      # Insert events in specific order
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_1)
      # Ensure different timestamps
      Process.sleep(1)
      :ok = KillmailStore.insert_event(@system_id_2, @test_killmail_2)
      Process.sleep(1)
      :ok = KillmailStore.insert_event(@system_id_1, @test_killmail_3)

      # Fetch all events
      {:ok, events} = KillmailStore.fetch_for_client(client_id, [@system_id_1, @system_id_2])

      # Should be 3 events in chronological order
      assert length(events) == 3

      event_ids = Enum.map(events, &elem(&1, 0))
      assert event_ids == Enum.sort(event_ids)

      # Verify the order matches insertion order
      [first, second, third] = events
      # @test_killmail_1
      assert elem(first, 2)["killmail_id"] == 12345
      # @test_killmail_2
      assert elem(second, 2)["killmail_id"] == 12346
      # @test_killmail_3
      assert elem(third, 2)["killmail_id"] == 12347
    end
  end
end
