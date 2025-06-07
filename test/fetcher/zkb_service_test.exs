defmodule WandererKills.Fetcher.ZkbServiceTest do
  use ExUnit.Case, async: true
  import Mox

  @moduletag :fetcher

  alias WandererKills.Fetcher.ZkbService
  alias WandererKills.TestHelpers
  alias WandererKills.Zkb.Client.Mock, as: ZkbClient

  setup :verify_on_exit!

  setup do
    TestHelpers.clear_all_caches()
    :ok
  end

  describe "fetch_killmail/2" do
    test "successfully fetches a killmail" do
      killmail_id = 123_456
      killmail = TestHelpers.generate_test_data(:killmail, killmail_id)

      ZkbClient
      |> expect(:fetch_killmail, fn ^killmail_id -> {:ok, killmail} end)

      assert {:ok, ^killmail} = ZkbService.fetch_killmail(killmail_id, ZkbClient)
    end

    test "handles killmail not found (nil response)" do
      killmail_id = 999_999

      ZkbClient
      |> expect(:fetch_killmail, fn ^killmail_id -> {:ok, nil} end)

      assert {:error, error} = ZkbService.fetch_killmail(killmail_id, ZkbClient)
      assert error.domain == :zkb
      assert error.type == :not_found
      assert String.contains?(error.message, "not found")
    end

    test "handles client errors" do
      killmail_id = 123_456

      ZkbClient
      |> expect(:fetch_killmail, fn ^killmail_id -> {:error, :rate_limited} end)

      assert {:error, :rate_limited} = ZkbService.fetch_killmail(killmail_id, ZkbClient)
    end

    test "validates killmail ID format" do
      assert {:error, error} = ZkbService.fetch_killmail("invalid", ZkbClient)
      assert error.domain == :validation
      assert String.contains?(error.message, "Invalid killmail ID format")
    end

    test "validates positive killmail ID" do
      assert {:error, error} = ZkbService.fetch_killmail(-1, ZkbClient)
      assert error.domain == :validation
    end
  end

  describe "fetch_system_killmails/4" do
    test "successfully fetches system killmails" do
      system_id = 30_000_142
      killmail1 = TestHelpers.generate_test_data(:killmail, 123)
      killmail2 = TestHelpers.generate_test_data(:killmail, 456)
      killmails = [killmail1, killmail2]

      ZkbClient
      |> expect(:fetch_system_killmails, fn ^system_id -> {:ok, killmails} end)

      assert {:ok, ^killmails} = ZkbService.fetch_system_killmails(system_id, 10, 24, ZkbClient)
    end

    test "handles empty killmail list" do
      system_id = 30_000_142

      ZkbClient
      |> expect(:fetch_system_killmails, fn ^system_id -> {:ok, []} end)

      assert {:ok, []} = ZkbService.fetch_system_killmails(system_id, 10, 24, ZkbClient)
    end

    test "handles client errors" do
      system_id = 30_000_142

      ZkbClient
      |> expect(:fetch_system_killmails, fn ^system_id -> {:error, :timeout} end)

      assert {:error, :timeout} = ZkbService.fetch_system_killmails(system_id, 10, 24, ZkbClient)
    end

    test "validates system ID format" do
      assert {:error, error} = ZkbService.fetch_system_killmails("invalid", 10, 24, ZkbClient)
      assert error.domain == :validation
      assert String.contains?(error.message, "Invalid system ID format")
    end

    test "validates positive system ID" do
      assert {:error, error} = ZkbService.fetch_system_killmails(-1, 10, 24, ZkbClient)
      assert error.domain == :validation
    end
  end

  describe "get_system_kill_count/2" do
    test "successfully gets kill count" do
      system_id = 30_000_142
      expected_count = 42

      ZkbClient
      |> expect(:get_system_kill_count, fn ^system_id -> {:ok, expected_count} end)

      assert {:ok, ^expected_count} = ZkbService.get_system_kill_count(system_id, ZkbClient)
    end

    test "handles client errors" do
      system_id = 30_000_142

      ZkbClient
      |> expect(:get_system_kill_count, fn ^system_id -> {:error, :not_found} end)

      assert {:error, :not_found} = ZkbService.get_system_kill_count(system_id, ZkbClient)
    end

    test "validates system ID format" do
      assert {:error, error} = ZkbService.get_system_kill_count("invalid", ZkbClient)
      assert error.domain == :validation
      assert String.contains?(error.message, "Invalid system ID format")
    end

    test "validates positive system ID" do
      assert {:error, error} = ZkbService.get_system_kill_count(-1, ZkbClient)
      assert error.domain == :validation
    end
  end
end
