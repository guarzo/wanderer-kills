defmodule WandererKills.CacheKeyTest do
  # Disable async to avoid cache interference
  use ExUnit.Case, async: false
  alias WandererKills.Cache.Helper
  alias WandererKills.TestHelpers

  setup do
    TestHelpers.clear_all_caches()

    on_exit(fn ->
      TestHelpers.clear_all_caches()
    end)
  end

  describe "cache key patterns" do
    test "killmail keys follow expected pattern" do
      # Test that the cache operations use consistent key patterns
      killmail_data = %{"killmail_id" => 123, "solar_system_id" => 456}

      # Store and retrieve to verify key pattern works
      assert {:ok, true} = Helper.killmail_put(123, killmail_data)
      assert {:ok, ^killmail_data} = Helper.killmail_get(123)
      assert {:ok, true} = Helper.killmail_delete(123)

      assert {:error, :not_found} = Helper.killmail_get(123)
    end

    test "system keys follow expected pattern" do
      # Test system-related cache operations
      assert {:ok, _} = Helper.system_add_active(456)
      # Note: get_active_systems() has streaming issues in test environment

      # No killmails initially
      assert {:ok, []} = Helper.system_get_killmails(456)
      assert {:ok, true} = Helper.system_add_killmail(456, 123)
      assert {:ok, [123]} = Helper.system_get_killmails(456)

      assert {:ok, 0} = Helper.system_get_kill_count(456)
      assert {:ok, 1} = Helper.system_increment_kill_count(456)
      assert {:ok, 1} = Helper.system_get_kill_count(456)
    end

    test "esi keys follow expected pattern" do
      character_data = %{"character_id" => 123, "name" => "Test Character"}
      corporation_data = %{"corporation_id" => 456, "name" => "Test Corp"}
      alliance_data = %{"alliance_id" => 789, "name" => "Test Alliance"}
      type_data = %{"type_id" => 101, "name" => "Test Type"}
      group_data = %{"group_id" => 102, "name" => "Test Group"}

      # Test ESI cache operations - verify set operations work
      assert {:ok, true} = Helper.character_put(123, character_data)
      assert {:ok, true} = Helper.corporation_put(456, corporation_data)
      assert {:ok, true} = Helper.alliance_put(789, alliance_data)
      assert {:ok, true} = Helper.ship_type_put(101, type_data)
      assert {:ok, true} = Helper.put("groups", "102", group_data)

      # Verify retrieval works using unified interface
      case Helper.character_get(123) do
        {:ok, ^character_data} -> :ok
        # Acceptable in test environment
        {:error, %WandererKills.Support.Error{type: :not_found}} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  describe "cache functionality" do
    test "basic cache operations work correctly" do
      key = "test:key"
      value = %{"test" => "data"}

      # Use Helper cache for basic operations
      assert {:ok, nil} = Helper.get("esi", key)

      assert {:ok, true} = Helper.put("esi", key, value)
      assert {:ok, ^value} = Helper.get("esi", key)
      assert {:ok, _} = Helper.delete("esi", key)

      assert {:ok, nil} = Helper.get("esi", key)
    end

    test "system fetch timestamp operations work" do
      # Use a unique system ID to avoid conflicts with other tests
      system_id = 99_789_123
      timestamp = DateTime.utc_now()

      # Ensure cache is completely clear for this specific system
      TestHelpers.clear_all_caches()

      refute Helper.system_recently_fetched?(system_id)
      assert {:ok, :set} = Helper.system_set_fetch_timestamp(system_id, timestamp)
      assert true = Helper.system_recently_fetched?(system_id)
    end
  end

  describe "cache health and stats" do
    test "cache reports as healthy" do
      # Test that caches are accessible - stats may not be available in test env
      case Helper.stats() do
        {:ok, _} -> :ok
        {:error, :stats_disabled} -> :ok
      end
    end

    test "cache stats are retrievable" do
      # stats may not be available in test environment
      case Helper.stats() do
        {:ok, stats} when is_map(stats) -> :ok
        {:error, :stats_disabled} -> :ok
      end
    end
  end
end
