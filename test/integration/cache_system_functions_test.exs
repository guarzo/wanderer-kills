defmodule WandererKills.Integration.CacheSystemFunctionsTest do
  @moduledoc """
  Integration tests for Cache.Helper.system_* functions.

  Tests the coordination between system tracking, killmail caching,
  fetch timestamps, and active system management to ensure all
  components work together correctly.
  """

  use ExUnit.Case, async: false
  use WandererKills.TestCase

  alias WandererKills.Cache.Helper

  @test_system_id 30_002_187
  @test_killmail_ids [123_456, 789_012, 345_678, 901_234]

  describe "system killmail tracking integration" do
    setup do
      # Clear any existing data for test system
      Helper.delete("systems", "killmails:#{@test_system_id}")
      Helper.delete("systems", "active:#{@test_system_id}")
      Helper.delete("systems", "last_fetch:#{@test_system_id}")
      Helper.delete("systems", "kill_count:#{@test_system_id}")
      Helper.delete("systems", "cached_killmails:#{@test_system_id}")

      :ok
    end

    test "complete system killmail workflow" do
      # Initially, system should have no killmails
      assert {:ok, []} = Helper.system_get_killmails(@test_system_id)

      # Add killmails one by one
      Enum.each(@test_killmail_ids, fn killmail_id ->
        assert {:ok, true} = Helper.system_add_killmail(@test_system_id, killmail_id)
      end)

      # Verify all killmails are tracked
      assert {:ok, tracked_killmails} = Helper.system_get_killmails(@test_system_id)
      assert length(tracked_killmails) == length(@test_killmail_ids)

      # All killmail IDs should be present (order may vary due to prepending)
      Enum.each(@test_killmail_ids, fn killmail_id ->
        assert killmail_id in tracked_killmails,
               "Killmail #{killmail_id} not found in #{inspect(tracked_killmails)}"
      end)

      # Adding duplicate killmail should not increase count
      first_killmail = List.first(@test_killmail_ids)
      assert {:ok, true} = Helper.system_add_killmail(@test_system_id, first_killmail)

      assert {:ok, final_killmails} = Helper.system_get_killmails(@test_system_id)
      assert length(final_killmails) == length(@test_killmail_ids)

      # Test replacing killmail list entirely
      new_killmail_ids = [999_888, 777_666]
      assert {:ok, true} = Helper.system_put_killmails(@test_system_id, new_killmail_ids)

      assert {:ok, ^new_killmail_ids} = Helper.system_get_killmails(@test_system_id)
    end

    test "system kill count tracking" do
      # Initially should be 0
      assert {:ok, 0} = Helper.system_get_kill_count(@test_system_id)

      # Increment kill count
      assert {:ok, 1} = Helper.system_increment_kill_count(@test_system_id)
      assert {:ok, 2} = Helper.system_increment_kill_count(@test_system_id)
      assert {:ok, 3} = Helper.system_increment_kill_count(@test_system_id)

      # Verify final count
      assert {:ok, 3} = Helper.system_get_kill_count(@test_system_id)

      # Test setting specific count
      assert {:ok, true} = Helper.system_put_kill_count(@test_system_id, 10)
      assert {:ok, 10} = Helper.system_get_kill_count(@test_system_id)

      # Increment from specific value
      assert {:ok, 11} = Helper.system_increment_kill_count(@test_system_id)
      assert {:ok, 11} = Helper.system_get_kill_count(@test_system_id)
    end

    test "system fetch timestamp management" do
      current_time = System.system_time(:second)

      # Initially should not have a timestamp
      assert {:ok, 0} = Helper.system_get_last_fetch(@test_system_id)

      # Mark system as fetched
      assert {:ok, true} = Helper.system_mark_last_fetch(@test_system_id)

      # Should now have a recent timestamp
      assert {:ok, timestamp} = Helper.system_get_last_fetch(@test_system_id)
      # Allow 5 second tolerance
      assert timestamp > current_time - 5
      assert timestamp <= System.system_time(:second)

      # Test recently fetched logic
      assert {:ok, true} = Helper.system_last_fetch_recent?(@test_system_id)

      # Test with custom threshold (should be recent within 60 minutes)
      assert {:ok, true} = Helper.system_last_fetch_recent?(@test_system_id, 60)

      # Test with very short threshold (should not be recent within 0 minutes)
      assert {:ok, false} = Helper.system_last_fetch_recent?(@test_system_id, 0)

      # Test setting specific timestamp
      # 2 hours ago
      old_timestamp = current_time - 7200
      assert {:ok, true} = Helper.system_put_last_fetch(@test_system_id, old_timestamp)

      # Should not be recently fetched with default threshold (30 minutes)
      assert {:ok, false} = Helper.system_last_fetch_recent?(@test_system_id)

      # But should be recent with larger threshold (3 hours)
      assert {:ok, true} = Helper.system_last_fetch_recent?(@test_system_id, 180)
    end

    test "active systems management" do
      # System should not initially be in active list
      assert {:ok, active_systems} = Helper.system_get_active_systems()
      refute @test_system_id in active_systems

      # Add system to active list
      assert {:ok, true} = Helper.system_add_active(@test_system_id)

      # Should now be in active list
      assert {:ok, active_systems} = Helper.system_get_active_systems()
      assert @test_system_id in active_systems

      # Adding again should not cause issues
      assert {:ok, true} = Helper.system_add_active(@test_system_id)
      assert {:ok, active_systems} = Helper.system_get_active_systems()
      assert @test_system_id in active_systems

      # Count should still only include it once
      system_count = Enum.count(active_systems, &(&1 == @test_system_id))
      assert system_count == 1
    end

    test "cached killmails storage" do
      sample_killmails = [
        %{"killmail_id" => 111, "solar_system_id" => @test_system_id},
        %{"killmail_id" => 222, "solar_system_id" => @test_system_id}
      ]

      # Initially should be empty
      assert {:ok, []} = Helper.system_get_cached_killmails(@test_system_id)

      # Store cached killmails
      assert {:ok, true} = Helper.system_put_cached_killmails(@test_system_id, sample_killmails)

      # Retrieve and verify
      assert {:ok, ^sample_killmails} = Helper.system_get_cached_killmails(@test_system_id)

      # Test overwriting
      new_killmails = [%{"killmail_id" => 333, "solar_system_id" => @test_system_id}]
      assert {:ok, true} = Helper.system_put_cached_killmails(@test_system_id, new_killmails)

      assert {:ok, ^new_killmails} = Helper.system_get_cached_killmails(@test_system_id)
    end
  end

  describe "system cache coordination scenarios" do
    setup do
      # Clear test data
      Helper.delete("systems", "killmails:#{@test_system_id}")
      Helper.delete("systems", "active:#{@test_system_id}")
      Helper.delete("systems", "last_fetch:#{@test_system_id}")
      Helper.delete("systems", "kill_count:#{@test_system_id}")
      Helper.delete("systems", "cached_killmails:#{@test_system_id}")

      :ok
    end

    test "typical killmail processing workflow" do
      # Simulate discovering a new active system
      assert {:ok, true} = Helper.system_add_active(@test_system_id)

      # Process some killmails for this system
      killmail_1 = 555_111
      killmail_2 = 555_222

      # Track individual killmails
      assert {:ok, true} = Helper.system_add_killmail(@test_system_id, killmail_1)
      assert {:ok, true} = Helper.system_add_killmail(@test_system_id, killmail_2)

      # Update kill counts
      assert {:ok, 1} = Helper.system_increment_kill_count(@test_system_id)
      assert {:ok, 2} = Helper.system_increment_kill_count(@test_system_id)

      # Mark system as recently fetched
      assert {:ok, true} = Helper.system_mark_last_fetch(@test_system_id)

      # Store enriched killmail data
      enriched_killmails = [
        %{"killmail_id" => killmail_1, "enriched" => true},
        %{"killmail_id" => killmail_2, "enriched" => true}
      ]

      assert {:ok, true} = Helper.system_put_cached_killmails(@test_system_id, enriched_killmails)

      # Verify complete state
      assert {:ok, [^killmail_2, ^killmail_1]} = Helper.system_get_killmails(@test_system_id)
      assert {:ok, 2} = Helper.system_get_kill_count(@test_system_id)
      assert {:ok, true} = Helper.system_last_fetch_recent?(@test_system_id)
      assert {:ok, ^enriched_killmails} = Helper.system_get_cached_killmails(@test_system_id)

      # System should be in active list
      assert {:ok, active_systems} = Helper.system_get_active_systems()
      assert @test_system_id in active_systems
    end

    test "cache eviction and refill scenario" do
      # Setup initial state
      assert {:ok, true} = Helper.system_add_killmail(@test_system_id, 999)
      assert {:ok, 1} = Helper.system_increment_kill_count(@test_system_id)
      assert {:ok, true} = Helper.system_mark_last_fetch(@test_system_id)

      # Simulate cache eviction by manually deleting
      assert {:ok, true} = Helper.delete("systems", "killmails:#{@test_system_id}")

      # System should now return empty killmails but keep other data
      assert {:ok, []} = Helper.system_get_killmails(@test_system_id)
      assert {:ok, 1} = Helper.system_get_kill_count(@test_system_id)
      assert {:ok, true} = Helper.system_last_fetch_recent?(@test_system_id)

      # Refill cache
      assert {:ok, true} = Helper.system_add_killmail(@test_system_id, 888)
      assert {:ok, [888]} = Helper.system_get_killmails(@test_system_id)
    end

    test "concurrent killmail additions" do
      # Simulate concurrent addition of killmails (tests the atomic update logic)
      killmail_ids = [111, 222, 333, 444, 555]

      # Add all killmails concurrently using Task.async_stream
      tasks =
        killmail_ids
        |> Task.async_stream(
          fn killmail_id ->
            Helper.system_add_killmail(@test_system_id, killmail_id)
          end,
          max_concurrency: 5
        )
        |> Enum.to_list()

      # All additions should succeed
      Enum.each(tasks, fn {:ok, result} ->
        assert {:ok, true} = result
      end)

      # Verify all killmails are tracked
      assert {:ok, final_killmails} = Helper.system_get_killmails(@test_system_id)
      assert length(final_killmails) == length(killmail_ids)

      # All original killmail IDs should be present
      Enum.each(killmail_ids, fn killmail_id ->
        assert killmail_id in final_killmails
      end)
    end

    test "multiple systems independence" do
      system_2 = @test_system_id + 1

      # Setup data for both systems
      assert {:ok, true} = Helper.system_add_killmail(@test_system_id, 111)
      assert {:ok, true} = Helper.system_add_killmail(system_2, 222)

      assert {:ok, 1} = Helper.system_increment_kill_count(@test_system_id)
      assert {:ok, 1} = Helper.system_increment_kill_count(system_2)
      assert {:ok, 2} = Helper.system_increment_kill_count(system_2)

      assert {:ok, true} = Helper.system_add_active(@test_system_id)
      assert {:ok, true} = Helper.system_add_active(system_2)

      # Verify systems maintain independent state
      assert {:ok, [111]} = Helper.system_get_killmails(@test_system_id)
      assert {:ok, [222]} = Helper.system_get_killmails(system_2)

      assert {:ok, 1} = Helper.system_get_kill_count(@test_system_id)
      assert {:ok, 2} = Helper.system_get_kill_count(system_2)

      assert {:ok, active_systems} = Helper.system_get_active_systems()
      assert @test_system_id in active_systems
      assert system_2 in active_systems

      # Clean up system_2
      Helper.delete("systems", "killmails:#{system_2}")
      Helper.delete("systems", "active:#{system_2}")
      Helper.delete("systems", "kill_count:#{system_2}")
    end
  end

  describe "error handling and edge cases" do
    test "handles invalid system IDs gracefully" do
      invalid_system_id = -1

      # All operations should handle invalid IDs without crashing
      assert {:ok, []} = Helper.system_get_killmails(invalid_system_id)
      assert {:ok, true} = Helper.system_add_killmail(invalid_system_id, 999)
      assert {:ok, 0} = Helper.system_get_kill_count(invalid_system_id)
      assert {:ok, 1} = Helper.system_increment_kill_count(invalid_system_id)
    end

    test "handles empty and nil data appropriately" do
      # Empty killmail list
      assert {:ok, true} = Helper.system_put_killmails(@test_system_id, [])
      assert {:ok, []} = Helper.system_get_killmails(@test_system_id)

      # Empty cached killmails
      assert {:ok, true} = Helper.system_put_cached_killmails(@test_system_id, [])
      assert {:ok, []} = Helper.system_get_cached_killmails(@test_system_id)
    end

    test "handles data corruption recovery" do
      # Manually corrupt cache by setting invalid data type
      namespaced_key = "systems:killmails:#{@test_system_id}"
      assert {:ok, true} = Cachex.put(:wanderer_cache, namespaced_key, "invalid_data")

      # system_add_killmail should recover from corruption
      assert {:ok, true} = Helper.system_add_killmail(@test_system_id, 999)

      # Should now have clean data
      assert {:ok, [999]} = Helper.system_get_killmails(@test_system_id)
    end
  end
end
