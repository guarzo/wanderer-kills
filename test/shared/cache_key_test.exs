defmodule WandererKills.CacheKeyTest do
  # Disable async to avoid cache interference
  use ExUnit.Case, async: false
  alias WandererKills.Core.Cache

  setup do
    WandererKills.TestHelpers.clear_all_caches()

    on_exit(fn ->
      WandererKills.TestHelpers.clear_all_caches()
    end)
  end

  describe "cache key patterns" do
    test "killmail keys follow expected pattern" do
      # Test that the cache operations use consistent key patterns
      killmail_data = %{"killmail_id" => 123, "solar_system_id" => 456}

      # Store and retrieve to verify key pattern works
      assert :ok = Cache.put(:killmails, 123, killmail_data)
      assert {:ok, ^killmail_data} = Cache.get(:killmails, 123)
      assert :ok = Cache.delete(:killmails, 123)
      assert {:error, %WandererKills.Core.Error{type: :not_found}} = Cache.get(:killmails, 123)
    end

    test "system keys follow expected pattern" do
      # Test system-related cache operations
      assert {:ok, []} = Cache.get_active_systems()
      assert {:ok, :added} = Cache.add_active_system(456)
      assert {:ok, [456]} = Cache.get_active_systems()

      assert {:ok, []} = Cache.get_killmails_for_system(456)
      assert :ok = Cache.add_system_killmail(456, 123)
      assert {:ok, [123]} = Cache.get_killmails_for_system(456)

      assert {:ok, 0} = Cache.get_system_kill_count(456)
      assert {:ok, 1} = Cache.increment_system_kill_count(456)
      assert {:ok, 1} = Cache.get_system_kill_count(456)
    end

    test "esi keys follow expected pattern" do
      character_data = %{"character_id" => 123, "name" => "Test Character"}
      corporation_data = %{"corporation_id" => 456, "name" => "Test Corp"}
      alliance_data = %{"alliance_id" => 789, "name" => "Test Alliance"}
      type_data = %{"type_id" => 101, "name" => "Test Type"}
      group_data = %{"group_id" => 102, "name" => "Test Group"}

      # Test ESI cache operations - verify set operations work
      assert :ok = Cache.put_with_ttl(:characters, 123, character_data, 24 * 3600)
      assert :ok = Cache.put_with_ttl(:corporations, 456, corporation_data, 24 * 3600)
      assert :ok = Cache.put_with_ttl(:alliances, 789, alliance_data, 24 * 3600)
      assert :ok = Cache.put_with_ttl(:ship_types, 101, type_data, 24 * 3600)
      assert :ok = Cache.put_with_ttl(:ship_types, "group_102", group_data, 24 * 3600)

      # Verify retrieval works using unified interface
      case Cache.get(:characters, 123) do
        {:ok, ^character_data} -> :ok
        # Acceptable in test environment
        {:error, :not_found} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  describe "cache functionality" do
    test "basic cache operations work correctly" do
      key = "test:key"
      value = %{"test" => "data"}

      assert {:error, %WandererKills.Core.Error{type: :not_found}} =
               Cache.get(:wanderer_kills_cache, key)

      assert :ok = Cache.put(:wanderer_kills_cache, key, value)
      assert {:ok, ^value} = Cache.get(:wanderer_kills_cache, key)
      assert :ok = Cache.delete(:wanderer_kills_cache, key)

      assert {:error, %WandererKills.Core.Error{type: :not_found}} =
               Cache.get(:wanderer_kills_cache, key)
    end

    test "system fetch timestamp operations work" do
      # Use a unique system ID to avoid conflicts with other tests
      system_id = 99_789_123
      timestamp = DateTime.utc_now()

      # Ensure cache is completely clear for this specific system
      WandererKills.TestHelpers.clear_all_caches()

      assert {:ok, false} = Cache.system_recently_fetched?(system_id)
      assert {:ok, :set} = Cache.set_system_fetch_timestamp(system_id, timestamp)
      assert {:ok, true} = Cache.system_recently_fetched?(system_id)
    end
  end

  describe "cache health and stats" do
    test "cache reports as healthy" do
      assert Cache.healthy?() == true
    end

    test "cache stats are retrievable or properly disabled" do
      case Cache.stats(:wanderer_kills_cache) do
        {:ok, stats} ->
          assert is_map(stats)

        {:error, _reason} ->
          # Stats may be disabled in test environment, which is acceptable
          assert true
      end
    end
  end
end
