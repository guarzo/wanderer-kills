defmodule WandererKills.Ingest.Killmails.StoreTest do
  use WandererKills.TestCase
  use WandererKills.Test.SharedContexts
  use WandererKills.Test.Tags

  alias WandererKills.Core.Storage.KillmailStore
  alias WandererKills.TestHelpers

  unit_test_tags()
  @moduletag area: :killmail_storage

  @system_id_1 30_000_142

  @test_killmail_1 %{
    "killmail_id" => 12_345,
    "kill_time" => "2024-01-01T12:00:00Z",
    "system_id" => @system_id_1,
    "victim" => %{
      "character_id" => 123,
      "ship_type_id" => 670,
      "damage_taken" => 1000
    },
    "attackers" => [],
    "zkb" => %{"totalValue" => 1000}
  }

  @test_killmail_2 %{
    "killmail_id" => 12_346,
    "kill_time" => "2024-01-01T12:30:00Z",
    "system_id" => @system_id_1,
    "victim" => %{
      "character_id" => 124,
      "ship_type_id" => 671,
      "damage_taken" => 2000
    },
    "attackers" => [],
    "zkb" => %{"totalValue" => 2000}
  }

  setup [:with_clean_environment, :with_kill_store]

  # Helper functions for migration period
  defp get_killmail_id(%WandererKills.Domain.Killmail{killmail_id: id}), do: id
  defp get_killmail_id(%{"killmail_id" => id}), do: id
  defp get_killmail_id(%{killmail_id: id}), do: id

  defp get_system_id(%WandererKills.Domain.Killmail{system_id: id}), do: id
  defp get_system_id(%{"system_id" => id}), do: id
  defp get_system_id(%{system_id: id}), do: id

  describe "killmail operations" do
    test "can store and retrieve a killmail" do
      killmail = @test_killmail_1
      {:ok, struct} = WandererKills.Domain.Killmail.new(killmail)
      :ok = KillmailStore.put(12_345, @system_id_1, struct)
      
      # During migration, store may return either structs or maps
      assert {:ok, retrieved} = KillmailStore.get(12_345)
      
      # Handle both struct and map cases
      killmail_id = get_killmail_id(retrieved)
      system_id = get_system_id(retrieved)
      
      assert killmail_id == 12_345
      assert system_id == @system_id_1
    end

    test "returns error for non-existent killmail" do
      assert {:error, _} = KillmailStore.get(999)
    end

    test "can delete a killmail" do
      killmail = TestHelpers.create_test_killmail(123)
      {:ok, struct} = WandererKills.Domain.Killmail.new(killmail)
      :ok = KillmailStore.put(123, @system_id_1, struct)
      :ok = KillmailStore.delete(123)
      assert {:error, _} = KillmailStore.get(123)
    end
  end

  describe "system operations" do
    test "can store and retrieve system killmails" do
      killmail1 = Map.put(@test_killmail_1, "killmail_id", 123)
      killmail2 = Map.put(@test_killmail_2, "killmail_id", 456)

      {:ok, struct1} = WandererKills.Domain.Killmail.new(killmail1)
      {:ok, struct2} = WandererKills.Domain.Killmail.new(killmail2)
      
      assert :ok = KillmailStore.put(123, @system_id_1, struct1)
      assert :ok = KillmailStore.put(456, @system_id_1, struct2)

      killmails = KillmailStore.list_by_system(@system_id_1)
      # During migration, may return structs or maps
      assert length(killmails) == 2
      killmail_ids = Enum.map(killmails, &get_killmail_id/1)
      assert Enum.sort(killmail_ids) == [123, 456]
    end

    test "returns empty list for system with no killmails" do
      killmails = KillmailStore.list_by_system(@system_id_1)
      assert killmails == []
    end

    test "can remove killmail from system" do
      killmail = Map.put(@test_killmail_1, "killmail_id", 123)
      {:ok, struct} = WandererKills.Domain.Killmail.new(killmail)
      assert :ok = KillmailStore.put(123, @system_id_1, struct)
      assert :ok = KillmailStore.delete(123)

      killmails = KillmailStore.list_by_system(@system_id_1)
      assert killmails == []
    end
  end

  describe "edge cases" do
    test "handles non-existent system" do
      non_existent_system = 99_999_999

      # Fetch for non-existent system should return empty list
      killmails = KillmailStore.list_by_system(non_existent_system)
      assert killmails == []
    end

    test "handles multiple systems correctly" do
      system_2 = 30_000_143

      killmail1 = Map.put(@test_killmail_1, "killmail_id", 123)
      killmail2 = Map.put(@test_killmail_2, "killmail_id", 456)

      # Store killmails in different systems
      assert :ok = KillmailStore.put(123, @system_id_1, killmail1)
      assert :ok = KillmailStore.put(456, system_2, killmail2)

      # Each system should only return its own killmails
      system_1_killmails = KillmailStore.list_by_system(@system_id_1)
      system_2_killmails = KillmailStore.list_by_system(system_2)
      
      assert length(system_1_killmails) == 1
      assert length(system_2_killmails) == 1
      assert get_killmail_id(hd(system_1_killmails)) == 123
      assert get_killmail_id(hd(system_2_killmails)) == 456

      assert length(system_1_killmails) == 1
      assert length(system_2_killmails) == 1
      assert hd(system_1_killmails)["killmail_id"] == 123
      assert hd(system_2_killmails)["killmail_id"] == 456
    end

    test "handles killmail updates correctly" do
      killmail = @test_killmail_1
      updated_killmail = Map.put(killmail, "updated", true)

      # Store initial killmail
      assert :ok = KillmailStore.put(12_345, @system_id_1, killmail)
      assert {:ok, ^killmail} = KillmailStore.get(12_345)

      # Update with new data
      assert :ok = KillmailStore.put(12_345, @system_id_1, updated_killmail)
      assert {:ok, ^updated_killmail} = KillmailStore.get(12_345)
    end
  end
end
