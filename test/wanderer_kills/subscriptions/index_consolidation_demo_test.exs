defmodule WandererKills.Subs.Subscriptions.IndexConsolidationDemoTest do
  @moduledoc """
  Demonstration test showing the successful consolidation of index patterns.

  This test file shows how the new shared test patterns eliminate duplication
  between character and system index tests while maintaining comprehensive
  coverage. Both index types now use identical test patterns with entity-specific
  configurations.
  """

  use ExUnit.Case, async: false
  import IndexTestHelpers

  alias WandererKills.Subs.Subscriptions.{CharacterIndex, SystemIndex}
  alias WandererKills.Core.Observability.{CharacterSubscriptionHealth, SystemSubscriptionHealth}

  describe "character index with shared patterns" do
    setup do
      setup_index(CharacterIndex, [123_456, 789_012, 345_678])
    end

    test "basic operations work identically", %{
      index_module: index_module,
      test_entities: test_entities
    } do
      test_basic_operations(index_module, test_entities)
    end

    test "statistics tracking is consistent", %{
      index_module: index_module,
      test_entities: test_entities
    } do
      test_statistics(index_module, test_entities)
    end

    test "health integration works", %{index_module: index_module, test_entities: test_entities} do
      test_health_integration(CharacterSubscriptionHealth, index_module, test_entities)
    end
  end

  describe "system index with shared patterns" do
    setup do
      setup_index(SystemIndex, [30_000_142, 30_000_144, 30_000_148])
    end

    test "basic operations work identically", %{
      index_module: index_module,
      test_entities: test_entities
    } do
      test_basic_operations(index_module, test_entities)
    end

    test "statistics tracking is consistent", %{
      index_module: index_module,
      test_entities: test_entities
    } do
      test_statistics(index_module, test_entities)
    end

    test "health integration works", %{index_module: index_module, test_entities: test_entities} do
      test_health_integration(SystemSubscriptionHealth, index_module, test_entities)
    end
  end

  describe "consolidation verification" do
    test "both indexes implement identical interfaces" do
      # Verify both modules export the same functions (from IndexBehaviour)
      char_exports = CharacterIndex.__info__(:functions) |> Enum.sort()
      sys_exports = SystemIndex.__info__(:functions) |> Enum.sort()

      assert char_exports == sys_exports
    end

    test "both health modules implement identical interfaces" do
      # Verify both health modules export the same functions (from HealthCheckBehaviour)
      char_health_exports = CharacterSubscriptionHealth.__info__(:functions) |> Enum.sort()
      sys_health_exports = SystemSubscriptionHealth.__info__(:functions) |> Enum.sort()

      assert char_health_exports == sys_health_exports
    end

    test "shared test patterns work for both entity types" do
      # This test demonstrates that the same test patterns can be used
      # for both character and system indexes without modification

      # Character index
      case CharacterIndex.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      CharacterIndex.clear()

      # System index
      case SystemIndex.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      SystemIndex.clear()

      # Use same test pattern on both
      char_entities = [123_456, 789_012, 345_678]
      sys_entities = [30_000_142, 30_000_144, 30_000_148]

      # Should work identically
      test_basic_operations(CharacterIndex, char_entities)
      test_basic_operations(SystemIndex, sys_entities)

      # Clear data instead of stopping shared GenServers
      CharacterIndex.clear()
      SystemIndex.clear()
    end
  end
end
