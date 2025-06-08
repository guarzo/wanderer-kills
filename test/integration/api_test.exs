defmodule WandererKills.ApiTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Mox

  alias WandererKills.TestHelpers
  alias WandererKillsWeb.Api

  @opts Api.init([])

  setup do
    WandererKills.TestHelpers.clear_all_caches()
    TestHelpers.setup_http_mocks()
    :ok
  end

  setup :verify_on_exit!

  describe "GET /ping" do
    test "returns pong" do
      conn = conn(:get, "/ping")
      conn = Api.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body == "pong"
    end
  end

  describe "GET /killmail/:id" do
    test "returns 400 for invalid ID" do
      conn = conn(:get, "/killmail/invalid")
      conn = Api.call(conn, @opts)

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "Invalid killmail ID"
    end

    test "returns 404 for non-existent killmail" do
      # Mock the HTTP client that ZKB actually uses internally
      WandererKills.Http.Client.Mock
      |> expect(:get_with_rate_limit, fn _url, _opts ->
        # ZKB returns empty array for not found
        {:ok, %{status: 200, body: "[]"}}
      end)

      conn = conn(:get, "/killmail/999999999")
      conn = Api.call(conn, @opts)

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "Killmail not found"
    end
  end

  describe "GET /system/:id/killmails" do
    test "returns 400 for invalid system ID" do
      conn = conn(:get, "/system/invalid/killmails")
      conn = Api.call(conn, @opts)

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "Invalid system ID"
    end
  end

  describe "GET /system_kill_count/:system_id" do
    test "returns 400 for invalid system ID" do
      conn = conn(:get, "/system_kill_count/invalid")
      conn = Api.call(conn, @opts)

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "Invalid system ID"
    end
  end

  describe "GET /kills_for_system/:system_id" do
    test "returns 400 for invalid system ID" do
      conn = conn(:get, "/kills_for_system/invalid")
      conn = Api.call(conn, @opts)

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "Invalid system ID"
    end

    test "redirects to /system_killmails/:system_id for valid ID" do
      conn = conn(:get, "/kills_for_system/123")
      conn = Api.call(conn, @opts)

      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/system_killmails/123"]
    end
  end

  describe "catch-all route" do
    test "returns 404 for unknown routes" do
      conn = conn(:get, "/unknown")
      conn = Api.call(conn, @opts)

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body)["error"] == "Not found"
    end
  end
end
