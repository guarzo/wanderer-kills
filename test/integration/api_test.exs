defmodule WandererKills.ApiTest do
  use ExUnit.Case, async: false
  use WandererKillsWeb.ConnCase
  use WandererKills.Test.SharedContexts
  use WandererKills.Test.Tags

  integration_test_tags()
  @moduletag area: :api

  setup [:with_clean_environment, :with_http_mocks]

  describe "GET /ping" do
    test "returns pong" do
      conn = build_conn() |> get("/ping")

      assert conn.status == 200
      assert conn.resp_body == "pong"
    end
  end

  describe "GET /api/v1/killmail/:killmail_id" do
    test "returns 400 for invalid ID" do
      conn = build_conn() |> get("/api/v1/killmail/invalid")

      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "Invalid killmail ID format"
    end

    test "returns 404 for non-existent killmail" do
      # Test the actual endpoint behavior without mocking specific internal calls
      # The implementation may use different HTTP client functions or caching
      conn = build_conn() |> get("/api/v1/killmail/999999999")

      assert conn.status == 404
      assert json_response(conn, 404)["error"] == "Killmail not found"
    end
  end

  describe "GET /api/v1/kills/count/:system_id" do
    test "returns 400 for invalid system ID" do
      conn = build_conn() |> get("/api/v1/kills/count/invalid")

      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "Invalid system ID format"
    end
  end

  describe "GET /api/v1/kills/system/:system_id" do
    test "returns 400 for invalid system ID" do
      conn = build_conn() |> get("/api/v1/kills/system/invalid")

      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "Invalid system ID format"
    end
  end

  describe "POST /api/v1/kills/systems" do
    test "returns 400 for invalid system IDs" do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/kills/systems", %{system_ids: ["invalid"]})

      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "Invalid system IDs"
    end
  end

  describe "GET /api/v1/kills/cached/:system_id" do
    test "returns 400 for invalid system ID" do
      conn = build_conn() |> get("/api/v1/kills/cached/invalid")

      assert conn.status == 400
      assert json_response(conn, 400)["error"] == "Invalid system ID format"
    end
  end

  describe "unknown routes" do
    test "returns 404 for unknown API routes" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get("/api/v1/unknown")

      assert conn.status == 404
      assert json_response(conn, 404)["error"] == "Not Found"
    end
  end
end
