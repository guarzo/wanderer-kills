defmodule WandererKills.CacheKeyTest do
  use ExUnit.Case, async: true
  alias WandererKills.Cache

  describe "cache key patterns" do
    test "killmail keys follow expected pattern" do
      # Test that the cache operations use consistent key patterns
      killmail_data = %{"killmail_id" => 123, "solar_system_id" => 456}

      # Store and retrieve to verify key pattern works
      assert :ok = Cache.set_killmail(123, killmail_data)
      assert {:ok, ^killmail_data} = Cache.get_killmail(123)
      assert :ok = Cache.delete_killmail(123)
      assert {:error, :not_found} = Cache.get_killmail(123)
    end

    test "system keys follow expected pattern" do
      # Test system-related cache operations
      assert {:ok, []} = Cache.get_active_systems()
      assert :ok = Cache.add_active_system(456)
      assert {:ok, [456]} = Cache.get_active_systems()

      assert {:ok, []} = Cache.get_system_killmails(456)
      assert :ok = Cache.add_system_killmail(456, 123)
      assert {:ok, [123]} = Cache.get_system_killmails(456)

      assert {:ok, 0} = Cache.get_system_kill_count(456)
      assert :ok = Cache.increment_system_kill_count(456)
      assert {:ok, 1} = Cache.get_system_kill_count(456)
    end

    test "esi keys follow expected pattern" do
      character_data = %{"character_id" => 123, "name" => "Test Character"}
      corporation_data = %{"corporation_id" => 456, "name" => "Test Corp"}
      alliance_data = %{"alliance_id" => 789, "name" => "Test Alliance"}
      type_data = %{"type_id" => 101, "name" => "Test Type"}
      group_data = %{"group_id" => 102, "name" => "Test Group"}

      # Test ESI cache operations
      assert :ok = Cache.set_character_info(123, character_data)
      assert {:ok, ^character_data} = Cache.get_character_info(123)

      assert :ok = Cache.set_corporation_info(456, corporation_data)
      assert {:ok, ^corporation_data} = Cache.get_corporation_info(456)

      assert :ok = Cache.set_alliance_info(789, alliance_data)
      assert {:ok, ^alliance_data} = Cache.get_alliance_info(789)

      assert :ok = Cache.set_type_info(101, type_data)
      assert {:ok, ^type_data} = Cache.get_type_info(101)

      assert :ok = Cache.set_group_info(102, group_data)
      assert {:ok, ^group_data} = Cache.get_group_info(102)
    end
  end

  describe "cache functionality" do
    test "basic cache operations work correctly" do
      key = "test:key"
      value = %{"test" => "data"}

      assert {:error, :not_found} = Cache.get(key)
      assert :ok = Cache.set(key, value)
      assert {:ok, ^value} = Cache.get(key)
      assert :ok = Cache.del(key)
      assert {:error, :not_found} = Cache.get(key)
    end

    test "system fetch timestamp operations work" do
      system_id = 789
      timestamp = DateTime.utc_now()

      assert {:ok, false} = Cache.system_recently_fetched?(system_id)
      assert :ok = Cache.set_system_fetch_timestamp(system_id, timestamp)
      assert {:ok, true} = Cache.system_recently_fetched?(system_id)
    end
  end

  describe "cache health and stats" do
    test "cache reports as healthy" do
      assert Cache.healthy?() == true
    end

    test "cache stats are retrievable or properly disabled" do
      case Cache.stats() do
        {:ok, stats} ->
          assert is_map(stats)

        {:error, :stats_disabled} ->
          # Stats may be disabled in test environment, which is acceptable
          assert true

        {:error, reason} ->
          flunk("Unexpected error getting cache stats: #{inspect(reason)}")
      end
    end
  end
end
