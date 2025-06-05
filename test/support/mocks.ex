defmodule WandererKills.Data.Sources.ZkbClient.Mock do
  @moduledoc """
  Mock implementation of ZkbClient for testing.
  """

  @behaviour WandererKills.Data.Sources.ZkbClientBehaviour

  @impl true
  def fetch_killmail(killmail_id) do
    {:ok, create_test_killmail(killmail_id)}
  end

  @impl true
  def fetch_system_killmails(_system_id) do
    {:ok, [create_test_killmail(123), create_test_killmail(456)]}
  end

  @impl true
  def fetch_system_kill_count(_system_id) do
    {:ok, 42}
  end

  @impl true
  def fetch_system_killmails_esi(_system_id) do
    {:ok, [create_test_killmail(123), create_test_killmail(456)]}
  end

  @impl true
  def enrich_killmail(killmail) do
    {:ok, Map.put(killmail, "enriched", true)}
  end

  @impl true
  def get_system_kill_count(system_id) do
    fetch_system_kill_count(system_id)
  end

  # Helper function to create test data
  defp create_test_killmail(killmail_id) do
    %{
      "killmail_id" => killmail_id,
      "killID" => killmail_id,
      "killTime" => "2024-01-01T00:00:00Z",
      "solarSystemID" => 30_000_142,
      "victim" => %{
        "characterID" => 12_345,
        "corporationID" => 67_890,
        "allianceID" => 54_321,
        "shipTypeID" => 1234
      },
      "attackers" => [
        %{
          "characterID" => 11_111,
          "corporationID" => 22_222,
          "allianceID" => 33_333,
          "shipTypeID" => 5678,
          "finalBlow" => true
        }
      ],
      "zkb" => %{
        "locationID" => 50_000_001,
        "hash" => "abc123",
        "fittedValue" => 1_000_000.0,
        "totalValue" => 1_500_000.0,
        "points" => 1,
        "npc" => false,
        "solo" => true,
        "awox" => false
      }
    }
  end
end
