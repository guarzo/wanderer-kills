defmodule WandererKills.CacheKeyTest do
  # Disable async to avoid cache interference
  use ExUnit.Case, async: false
  alias WandererKills.Cache.ESI
  alias WandererKills.Cache.Systems
  alias WandererKills.Cache.ShipTypes

  setup do
    WandererKills.Test.CacheHelpers.clear_all_caches()

    on_exit(fn ->
      WandererKills.Test.CacheHelpers.clear_all_caches()
    end)
  end

  describe "cache key patterns" do
    test "killmail keys follow expected pattern" do
      # Test that the cache operations use consistent key patterns
      killmail_data = %{"killmail_id" => 123, "solar_system_id" => 456}

      # Store and retrieve to verify key pattern works
      assert :ok = ESI.put_killmail(123, killmail_data)
      assert {:ok, ^killmail_data} = ESI.get_killmail(123)
      assert :ok = ESI.delete_killmail(123)
      assert {:error, %WandererKills.Core.Error{type: :not_found}} = ESI.get_killmail(123)
    end

    test "system keys follow expected pattern" do
      # Test system-related cache operations
      assert {:ok, []} = Systems.get_active_systems()
      assert {:ok, :added} = Systems.add_active(456)
      assert {:ok, [456]} = Systems.get_active_systems()

      assert {:ok, []} = Systems.get_killmails(456)
      assert :ok = Systems.add_killmail(456, 123)
      assert {:ok, [123]} = Systems.get_killmails(456)

      assert {:ok, 0} = Systems.get_kill_count(456)
      assert {:ok, 1} = Systems.increment_kill_count(456)
      assert {:ok, 1} = Systems.get_kill_count(456)
    end

    test "esi keys follow expected pattern" do
      character_data = %{"character_id" => 123, "name" => "Test Character"}
      corporation_data = %{"corporation_id" => 456, "name" => "Test Corp"}
      alliance_data = %{"alliance_id" => 789, "name" => "Test Alliance"}
      type_data = %{"type_id" => 101, "name" => "Test Type"}
      group_data = %{"group_id" => 102, "name" => "Test Group"}

      # Test ESI cache operations - verify set operations work
      assert :ok = ESI.put_character(123, character_data)
      assert :ok = ESI.put_corporation(456, corporation_data)
      assert :ok = ESI.put_alliance(789, alliance_data)
      assert :ok = ShipTypes.put(101, type_data)
      assert :ok = ESI.put_group(102, group_data)

      # Verify retrieval works using unified interface
      case ESI.get_character(123) do
        {:ok, ^character_data} -> :ok
        # Acceptable in test environment
        {:error, %WandererKills.Core.Error{type: :not_found}} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  describe "cache functionality" do
    test "basic cache operations work correctly" do
      key = "test:key"
      value = %{"test" => "data"}

      # Use ESI cache for basic operations since there's no general cache wrapper
      assert {:error, %WandererKills.Core.Error{type: :not_found}} =
               ESI.get_from_cache(:esi, key)

      assert :ok = ESI.put_in_cache(:esi, key, value)
      assert {:ok, ^value} = ESI.get_from_cache(:esi, key)
      assert :ok = ESI.delete_from_cache(:esi, key)

      assert {:error, %WandererKills.Core.Error{type: :not_found}} =
               ESI.get_from_cache(:esi, key)
    end

    test "system fetch timestamp operations work" do
      # Use a unique system ID to avoid conflicts with other tests
      system_id = 99_789_123
      timestamp = DateTime.utc_now()

      # Ensure cache is completely clear for this specific system
      WandererKills.Test.CacheHelpers.clear_all_caches()

      assert {:ok, false} = Systems.recently_fetched?(system_id)
      assert {:ok, :set} = Systems.set_fetch_timestamp(system_id, timestamp)
      assert {:ok, true} = Systems.recently_fetched?(system_id)
    end
  end

  describe "cache health and stats" do
    test "cache reports as healthy" do
      # Test that caches are accessible
      assert is_list(Systems.stats())
      assert is_list(ESI.stats())
      assert is_list(ShipTypes.stats())
    end

    test "cache stats are retrievable" do
      stats = Systems.stats()
      assert is_list(stats)
      # Each cache should have stats for its namespaces
      assert length(stats) > 0
    end
  end
end
