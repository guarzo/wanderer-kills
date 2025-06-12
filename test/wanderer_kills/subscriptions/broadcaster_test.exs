defmodule WandererKills.Subscriptions.BroadcasterTest do
  use ExUnit.Case, async: false

  alias WandererKills.Subscriptions.Broadcaster
  alias WandererKills.Support.PubSubTopics

  @pubsub_name WandererKills.PubSub

  # Helper function to collect messages up to a count or timeout
  defp receive_messages_until(expected_count, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    collect_messages([], expected_count, deadline)
  end

  defp collect_messages(messages, expected_count, _deadline)
       when length(messages) >= expected_count do
    messages
  end

  defp collect_messages(messages, expected_count, deadline) do
    remaining_time = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      msg -> collect_messages([msg | messages], expected_count, deadline)
    after
      remaining_time -> messages
    end
  end

  setup do
    # Subscribe to relevant topics for testing
    system_id = 30_000_142
    system_topic = PubSubTopics.system_topic(system_id)
    detailed_topic = PubSubTopics.system_detailed_topic(system_id)
    all_systems_topic = PubSubTopics.all_systems_topic()

    Phoenix.PubSub.subscribe(@pubsub_name, system_topic)
    Phoenix.PubSub.subscribe(@pubsub_name, detailed_topic)
    Phoenix.PubSub.subscribe(@pubsub_name, all_systems_topic)

    {:ok, system_id: system_id}
  end

  describe "broadcast_killmail_update/2" do
    test "broadcasts to all relevant topics", %{system_id: system_id} do
      kills = [
        %{
          "killmail_id" => 123,
          "killmail_time" => "2024-01-01T00:00:00Z",
          "victim" => %{"ship_type_id" => 587}
        },
        %{
          "killmail_id" => 124,
          "killmail_time" => "2024-01-01T00:01:00Z",
          "victim" => %{"ship_type_id" => 588}
        }
      ]

      # Broadcast the update
      assert :ok = Broadcaster.broadcast_killmail_update(system_id, kills)

      # Should receive on system topic
      assert_receive %{
        type: :killmail_update,
        system_id: ^system_id,
        kills: ^kills,
        timestamp: %DateTime{}
      }

      # Should receive on detailed system topic
      assert_receive %{
        type: :killmail_update,
        system_id: ^system_id,
        kills: ^kills,
        timestamp: %DateTime{}
      }

      # Should receive on all systems topic
      assert_receive %{
        type: :killmail_update,
        system_id: ^system_id,
        kills: ^kills,
        timestamp: %DateTime{}
      }
    end

    test "broadcasts empty kills list", %{system_id: system_id} do
      kills = []

      assert :ok = Broadcaster.broadcast_killmail_update(system_id, kills)

      # Should still receive messages on all topics
      assert_receive %{
        type: :killmail_update,
        system_id: ^system_id,
        kills: [],
        timestamp: %DateTime{}
      }
    end

    test "logs broadcast with kill count", %{system_id: system_id} do
      kills = [
        %{"killmail_id" => 125},
        %{"killmail_id" => 126},
        %{"killmail_id" => 127}
      ]

      assert :ok = Broadcaster.broadcast_killmail_update(system_id, kills)

      # Verify broadcast was received
      assert_receive %{
        type: :killmail_update,
        system_id: ^system_id,
        kills: ^kills
      }
    end

    test "handles large kill lists", %{system_id: system_id} do
      # Generate a large list of kills
      kills =
        Enum.map(1..100, fn i ->
          %{
            "killmail_id" => 1000 + i,
            "killmail_time" => "2024-01-01T00:00:00Z",
            "victim" => %{"ship_type_id" => 587}
          }
        end)

      assert :ok = Broadcaster.broadcast_killmail_update(system_id, kills)

      assert_receive %{
        type: :killmail_update,
        system_id: ^system_id,
        kills: received_kills,
        timestamp: %DateTime{}
      }

      assert length(received_kills) == 100
    end

    test "message includes timestamp", %{system_id: system_id} do
      kills = [%{"killmail_id" => 128}]

      before_broadcast = DateTime.utc_now()
      assert :ok = Broadcaster.broadcast_killmail_update(system_id, kills)
      after_broadcast = DateTime.utc_now()

      assert_receive %{
        type: :killmail_update,
        timestamp: timestamp
      }

      # Verify timestamp is within reasonable bounds
      assert DateTime.compare(timestamp, before_broadcast) in [:gt, :eq]
      assert DateTime.compare(timestamp, after_broadcast) in [:lt, :eq]
    end
  end

  describe "broadcast_killmail_count/2" do
    test "broadcasts count to all relevant topics", %{system_id: system_id} do
      count = 42

      assert :ok = Broadcaster.broadcast_killmail_count(system_id, count)

      # Should receive on system topic
      assert_receive %{
        type: :killmail_count_update,
        system_id: ^system_id,
        count: ^count,
        timestamp: %DateTime{}
      }

      # Should receive on detailed system topic
      assert_receive %{
        type: :killmail_count_update,
        system_id: ^system_id,
        count: ^count,
        timestamp: %DateTime{}
      }

      # Should NOT receive on all systems topic (count updates are system-specific)
      refute_receive %{type: :killmail_count_update}, 100
    end

    test "broadcasts count update", %{system_id: system_id} do
      count = 10

      assert :ok = Broadcaster.broadcast_killmail_count(system_id, count)

      # Verify broadcast was received
      assert_receive %{
        type: :killmail_count_update,
        system_id: ^system_id,
        count: ^count
      }
    end

    test "handles zero count", %{system_id: system_id} do
      count = 0

      assert :ok = Broadcaster.broadcast_killmail_count(system_id, count)

      assert_receive %{
        type: :killmail_count_update,
        system_id: ^system_id,
        count: 0,
        timestamp: %DateTime{}
      }
    end

    test "handles large counts", %{system_id: system_id} do
      count = 999_999

      assert :ok = Broadcaster.broadcast_killmail_count(system_id, count)

      assert_receive %{
        type: :killmail_count_update,
        system_id: ^system_id,
        count: 999_999,
        timestamp: %DateTime{}
      }
    end
  end

  describe "pubsub_name/0" do
    test "returns the correct PubSub name" do
      assert Broadcaster.pubsub_name() == WandererKills.PubSub
    end
  end

  describe "concurrent broadcasts" do
    test "handles concurrent broadcasts to same system", %{system_id: system_id} do
      # Spawn multiple processes to broadcast concurrently
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            kills = [%{"killmail_id" => 2000 + i}]
            Broadcaster.broadcast_killmail_update(system_id, kills)
          end)
        end)

      # Wait for all tasks to complete
      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))

      # Should receive all 10 messages (x3 for each topic)
      # Collect all messages within a reasonable timeout (increased for CI)
      received = receive_messages_until(30, 5000)

      assert length(received) >= 30
      assert Enum.all?(received, &(&1.type == :killmail_update))
    end

    test "handles broadcasts to different systems concurrently" do
      system_ids = [30_000_142, 30_000_143, 30_000_144]

      # Subscribe to all system topics
      Enum.each(system_ids, fn sys_id ->
        Phoenix.PubSub.subscribe(@pubsub_name, PubSubTopics.system_topic(sys_id))
      end)

      # Broadcast to different systems concurrently
      tasks =
        Enum.map(system_ids, fn sys_id ->
          Task.async(fn ->
            kills = [%{"killmail_id" => 3000 + sys_id}]
            Broadcaster.broadcast_killmail_update(sys_id, kills)
          end)
        end)

      # Wait for all tasks to complete
      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))

      # Verify we received messages for each system
      Enum.each(system_ids, fn sys_id ->
        assert_receive %{
          type: :killmail_update,
          system_id: ^sys_id
        }
      end)
    end
  end

  describe "error resilience" do
    test "handles invalid system_id types properly" do
      # The PubSubTopics module expects integer system_ids
      # Invalid types should raise FunctionClauseError
      invalid_ids = [nil, "not_an_id", 1.5, %{}, []]

      Enum.each(invalid_ids, fn invalid_id ->
        # These should raise due to the guard clause in PubSubTopics
        assert_raise FunctionClauseError, fn ->
          Broadcaster.broadcast_killmail_update(invalid_id, [])
        end

        assert_raise FunctionClauseError, fn ->
          Broadcaster.broadcast_killmail_count(invalid_id, 0)
        end
      end)
    end

    test "handles edge case system_ids" do
      # These are valid integers, so should work
      edge_ids = [-1, 0, 999_999_999]

      Enum.each(edge_ids, fn system_id ->
        # Should not raise with valid integers
        assert :ok = Broadcaster.broadcast_killmail_update(system_id, [])
        assert :ok = Broadcaster.broadcast_killmail_count(system_id, 0)
      end)
    end
  end
end
