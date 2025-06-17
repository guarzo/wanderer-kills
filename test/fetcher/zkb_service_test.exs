defmodule WandererKills.Ingest.Killmails.ZkbClientTest do
  use WandererKills.DataCase, async: false

  @moduletag :external

  alias WandererKills.Ingest.Http.Client.Mock, as: HttpClientMock
  alias WandererKills.Ingest.Killmails.ZkbClient, as: ZKB

  # Get base URL from config
  @base_url Application.compile_env(:wanderer_kills, :zkb)[:base_url]

  setup do
    # Configure the HTTP client to use the mock
    Application.put_env(:wanderer_kills, :http_client, HttpClientMock)

    on_exit(fn ->
      # Reset to default
      Application.delete_env(:wanderer_kills, :http_client)
    end)

    :ok
  end

  describe "fetch_killmail/1" do
    test "successfully fetches a killmail" do
      killmail_id = 123_456
      killmail = TestHelpers.generate_test_data(:killmail, killmail_id)

      HttpClientMock
      |> expect(:get_with_rate_limit, fn
        "#{@base_url}/killID/123456/", _opts ->
          {:ok, %{status: 200, body: Jason.encode!([killmail])}}
      end)

      assert {:ok, ^killmail} = ZKB.fetch_killmail(killmail_id)
    end

    test "handles killmail not found (nil response)" do
      killmail_id = 999_999

      HttpClientMock
      |> expect(:get_with_rate_limit, fn
        "#{@base_url}/killID/999999/", _opts ->
          {:ok, %{status: 200, body: "[]"}}
      end)

      assert {:error, error} = ZKB.fetch_killmail(killmail_id)
      assert error.domain == :zkb
      assert error.type == :not_found
      assert String.contains?(error.message, "not found")
    end

    test "handles client errors" do
      killmail_id = 123_456

      HttpClientMock
      |> expect(:get_with_rate_limit, fn
        "#{@base_url}/killID/123456/", _opts ->
          {:error, :rate_limited}
      end)

      assert {:error, :rate_limited} = ZKB.fetch_killmail(killmail_id)
    end

    test "validates killmail ID format" do
      assert {:error, error} = ZKB.fetch_killmail("invalid")
      assert error.domain == :validation
      assert String.contains?(error.message, "Invalid killmail ID format")
    end

    test "validates positive killmail ID" do
      assert {:error, error} = ZKB.fetch_killmail(-1)
      assert error.domain == :validation
    end
  end

  describe "fetch_system_killmails/2" do
    test "successfully fetches system killmails" do
      system_id = 30_000_142
      killmail1 = TestHelpers.generate_test_data(:killmail, 123)
      killmail2 = TestHelpers.generate_test_data(:killmail, 456)
      killmails = [killmail1, killmail2]

      HttpClientMock
      |> expect(:get_with_rate_limit, fn
        "#{@base_url}/systemID/30000142/", _opts ->
          {:ok, %{status: 200, body: Jason.encode!(killmails)}}
      end)

      # Using new API with options
      assert {:ok, ^killmails} =
               ZKB.fetch_system_killmails(system_id, limit: 10, past_seconds: 86_400)
    end

    test "successfully fetches system killmails without options" do
      system_id = 30_000_142
      killmail1 = TestHelpers.generate_test_data(:killmail, 123)
      killmail2 = TestHelpers.generate_test_data(:killmail, 456)
      killmails = [killmail1, killmail2]

      HttpClientMock
      |> expect(:get_with_rate_limit, fn
        "#{@base_url}/systemID/30000142/", _opts ->
          {:ok, %{status: 200, body: Jason.encode!(killmails)}}
      end)

      # Using new API without options
      assert {:ok, ^killmails} = ZKB.fetch_system_killmails(system_id)
    end

    test "handles empty killmail list" do
      system_id = 30_000_142

      HttpClientMock
      |> expect(:get_with_rate_limit, fn
        "#{@base_url}/systemID/30000142/", _opts ->
          {:ok, %{status: 200, body: "[]"}}
      end)

      assert {:ok, []} = ZKB.fetch_system_killmails(system_id, [])
    end

    test "handles client errors" do
      system_id = 30_000_142

      HttpClientMock
      |> expect(:get_with_rate_limit, fn
        "#{@base_url}/systemID/30000142/", _opts ->
          {:error, :timeout}
      end)

      assert {:error, :timeout} = ZKB.fetch_system_killmails(system_id, [])
    end

    test "validates system ID format" do
      assert {:error, error} = ZKB.fetch_system_killmails("invalid", [])
      assert error.domain == :validation
      assert String.contains?(error.message, "Invalid system ID format")
    end

    test "validates positive system ID" do
      assert {:error, error} = ZKB.fetch_system_killmails(-1, [])
      assert error.domain == :validation
    end
  end

  describe "get_system_killmail_count/1" do
    test "successfully gets kill count" do
      system_id = 30_000_142
      expected_count = 42

      # Create a list with 42 items (the function counts list length)
      kill_list = Enum.map(1..expected_count, fn id -> %{"killmail_id" => id} end)

      HttpClientMock
      |> expect(:get_with_rate_limit, fn
        "#{@base_url}/systemID/30000142/", _opts ->
          {:ok, %{status: 200, body: Jason.encode!(kill_list)}}
      end)

      assert {:ok, ^expected_count} = ZKB.get_system_killmail_count(system_id)
    end

    test "handles client errors" do
      system_id = 30_000_142

      HttpClientMock
      |> expect(:get_with_rate_limit, fn
        "#{@base_url}/systemID/30000142/", _opts ->
          {:error, :not_found}
      end)

      assert {:error, :not_found} = ZKB.get_system_killmail_count(system_id)
    end

    test "validates system ID format" do
      assert {:error, error} = ZKB.get_system_killmail_count("invalid")
      assert error.domain == :validation
      assert String.contains?(error.message, "Invalid system ID format")
    end

    test "validates positive system ID" do
      assert {:error, error} = ZKB.get_system_killmail_count(-1)
      assert error.domain == :validation
    end
  end
end
