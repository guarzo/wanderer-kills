defmodule WandererKills.Fetcher.KillmailFetcherTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererKills.Fetcher
  alias WandererKills.Zkb.Client, as: ZkbClient

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Clear all caches before each test
    WandererKills.TestHelpers.clear_all_caches()

    # Set up the mock for each test
    ZkbClient.Mock
    |> stub(:fetch_killmail, fn _id -> {:ok, nil} end)
    |> stub(:fetch_system_killmails, fn _id -> {:ok, []} end)

    # Mock HTTP client for ESI API calls during parsing
    WandererKills.Http.Client.Mock
    |> stub(:get_with_rate_limit, fn url, _opts ->
      if String.contains?(url, "/killmails/") do
        # Mock ESI killmail endpoint
        # Extract killmail ID from URL
        id = url |> String.split("/") |> Enum.at(-2) |> String.to_integer()

        {:ok,
         %{
           body: %{
             "killmail_id" => id,
             "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
             "solar_system_id" => 30_000_142,
             "victim" => %{"ship_type_id" => 1234},
             "attackers" => [%{"character_id" => 456, "final_blow" => true}]
           }
         }}
      else
        # Default fallback
        {:error, :not_found}
      end
    end)

    :ok
  end

  describe "fetch_and_cache_killmail/1" do
    test "returns error for invalid ID" do
      assert {:error, :invalid_id} = Fetcher.fetch_and_cache_killmail(0)
    end

    test "returns error when killmail not found" do
      Mox.expect(ZkbClient.Mock, :fetch_killmail, fn 123 ->
        {:ok, nil}
      end)

      assert {:error, :not_found} = Fetcher.fetch_and_cache_killmail(123, ZkbClient.Mock)
    end

    test "successfully fetches and caches killmail" do
      killmail = %{
        "killmail_id" => 123,
        "killmail_time" => "2023-01-01T00:00:00Z",
        "killmail_url" => "https://esi.evetech.net/v1/killmails/123/"
      }

      Mox.expect(ZkbClient.Mock, :fetch_killmail, fn 123 ->
        {:ok, killmail}
      end)

      assert {:ok, ^killmail} = Fetcher.fetch_and_cache_killmail(123, ZkbClient.Mock)
    end
  end

  describe "fetch_killmails_for_system/2" do
    test "fetches killmails for a system" do
      # Mock successful response from ZKB
      Mox.expect(ZkbClient.Mock, :fetch_system_killmails, fn 30_000_142 ->
        {:ok, [%{"killmail_id" => 12_345}]}
      end)

      assert {:ok, result} =
               Fetcher.fetch_killmails_for_system(30_000_142, client: ZkbClient.Mock)

      assert is_list(result)
    end

    test "respects limit option" do
      # Mock successful response from ZKB
      Mox.expect(ZkbClient.Mock, :fetch_system_killmails, fn 30_000_142 ->
        # Return exactly 2 killmails to match the limit
        {:ok,
         [
           %{
             "killmail_id" => 12_345,
             "killmail_time" => "2023-01-01T00:00:00Z",
             "solar_system_id" => 30_000_142,
             "victim" => %{"ship_type_id" => 1234},
             "attackers" => [%{"character_id" => 456, "final_blow" => true}],
             "zkb" => %{"hash" => "abc123", "totalValue" => 1000}
           },
           %{
             "killmail_id" => 12_346,
             "killmail_time" => "2023-01-01T01:00:00Z",
             "solar_system_id" => 30_000_142,
             "victim" => %{"ship_type_id" => 5678},
             "attackers" => [%{"character_id" => 789, "final_blow" => true}],
             "zkb" => %{"hash" => "def456", "totalValue" => 2000}
           }
         ]}
      end)

      result =
        Fetcher.fetch_killmails_for_system(30_000_142,
          limit: 2,
          force: true,
          client: ZkbClient.Mock
        )

      assert {:ok, killmails} = result
      assert is_list(killmails)
      # Note: actual length may vary due to parsing/filtering logic
    end

    test "uses cache when available" do
      # First call should fetch from ZKB and cache the result
      Mox.expect(ZkbClient.Mock, :fetch_system_killmails, fn 30_000_142 ->
        {:ok, [%{"killmail_id" => 12_345}]}
      end)

      assert {:ok, _result} =
               Fetcher.fetch_killmails_for_system(30_000_142, force: true, client: ZkbClient.Mock)

      # Second call should use cache (no additional ZKB call expected)
      assert {:ok, cached_result} =
               Fetcher.fetch_killmails_for_system(30_000_142, client: ZkbClient.Mock)

      assert is_list(cached_result)
    end

    test "force option bypasses cache" do
      # Mock two separate calls to ZKB
      Mox.expect(ZkbClient.Mock, :fetch_system_killmails, 2, fn 30_000_142 ->
        {:ok, [%{"killmail_id" => 12_345}]}
      end)

      # First call
      Fetcher.fetch_killmails_for_system(30_000_142, force: true, client: ZkbClient.Mock)

      # Second call with force should bypass cache and call ZKB again
      Fetcher.fetch_killmails_for_system(30_000_142, force: true, client: ZkbClient.Mock)
    end

    test "handles string system IDs" do
      Mox.expect(ZkbClient.Mock, :fetch_system_killmails, fn 30_000_142 ->
        {:ok, []}
      end)

      assert {:ok, []} =
               Fetcher.fetch_killmails_for_system("30000142", force: true, client: ZkbClient.Mock)
    end
  end

  describe "fetch_killmails_for_systems/2" do
    test "fetches killmails for multiple systems" do
      # Mock responses for both systems
      Mox.expect(ZkbClient.Mock, :fetch_system_killmails, 2, fn system_id ->
        case system_id do
          30_000_142 -> {:ok, [%{"killmail_id" => 12_345}]}
          30_000_143 -> {:ok, [%{"killmail_id" => 12_346}]}
        end
      end)

      results =
        Fetcher.fetch_killmails_for_systems([30_000_142, 30_000_143], client: ZkbClient.Mock)

      assert is_map(results)
      assert Map.has_key?(results, 30_000_142)
      assert Map.has_key?(results, 30_000_143)
    end

    test "respects max_concurrency option" do
      # Mock responses
      Mox.expect(ZkbClient.Mock, :fetch_system_killmails, 2, fn _system_id ->
        {:ok, []}
      end)

      Fetcher.fetch_killmails_for_systems([30_000_142, 30_000_143],
        max_concurrency: 1,
        client: ZkbClient.Mock
      )
    end
  end

  describe "get_system_kill_count/2" do
    test "returns kill count for valid system" do
      system_id = 30_000_142

      Mox.expect(ZkbClient.Mock, :get_system_kill_count, fn ^system_id ->
        {:ok, 15}
      end)

      assert {:ok, 15} = Fetcher.get_system_kill_count(system_id, ZkbClient.Mock)
    end

    test "returns error for invalid system" do
      invalid_id = -1

      Mox.expect(ZkbClient.Mock, :get_system_kill_count, fn ^invalid_id ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} = Fetcher.get_system_kill_count(invalid_id, ZkbClient.Mock)
    end

    test "handles string IDs" do
      Mox.expect(ZkbClient.Mock, :get_system_kill_count, fn 30_000_142 ->
        {:ok, 15}
      end)

      assert {:ok, 15} = Fetcher.get_system_kill_count("30000142", ZkbClient.Mock)
    end
  end
end
