defmodule WandererKills.Fetcher.KillmailFetcherTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererKills.Fetcher.Zkb.KillmailFetcher
  alias WandererKills.Zkb.Client.Mock, as: ZkbClient
  alias WandererKills.TestHelpers
  alias WandererKills.KillmailStore

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Clean up any existing state
    KillmailStore.cleanup_tables()
    :ok
  end

  describe "fetch_killmail/1" do
    test "successfully fetches and stores a killmail" do
      killmail = TestHelpers.create_test_killmail(123)

      ZkbClient
      |> expect(:fetch_killmail, fn 123 -> {:ok, killmail} end)

      assert {:ok, ^killmail} = KillmailFetcher.fetch_killmail(123, ZkbClient)
      assert {:ok, ^killmail} = WandererKills.KillmailStore.get_killmail(123)
    end

    test "handles invalid killmail ID" do
      ZkbClient
      |> expect(:fetch_killmail, fn 999 -> {:error, :not_found} end)

      assert {:error, :not_found} = KillmailFetcher.fetch_killmail(999, ZkbClient)
    end
  end

  describe "fetch_system_killmails/1" do
    test "successfully fetches and stores system killmails" do
      killmail1 = TestHelpers.create_test_killmail(123)
      killmail2 = TestHelpers.create_test_killmail(456)
      killmails = [killmail1, killmail2]

      ZkbClient
      |> expect(:fetch_system_killmails, fn 789 -> {:ok, killmails} end)

      assert {:ok, ^killmails} = KillmailFetcher.fetch_system_killmails(789, ZkbClient)
      assert {:ok, stored_killmails} = WandererKills.KillmailStore.get_killmails_for_system(789)
      assert length(stored_killmails) == 2
      assert Enum.map(stored_killmails, & &1) |> Enum.sort() == [123, 456]
    end

    test "handles system with no killmails" do
      ZkbClient
      |> expect(:fetch_system_killmails, fn 999 -> {:ok, []} end)

      assert {:ok, []} = KillmailFetcher.fetch_system_killmails(999, ZkbClient)
      assert {:ok, []} = WandererKills.KillmailStore.get_killmails_for_system(999)
    end

    test "handles error from zkb client" do
      ZkbClient
      |> expect(:fetch_system_killmails, fn 999 -> {:error, :timeout} end)

      assert {:error, :timeout} = KillmailFetcher.fetch_system_killmails(999, ZkbClient)
    end
  end
end
