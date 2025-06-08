defmodule WandererKills.ApiSmokeTest do
  use ExUnit.Case, async: false
  use WandererKillsWeb.ConnCase

  test "GET /ping returns pong" do
    conn = build_conn() |> get("/ping")
    assert conn.status == 200
    assert conn.resp_body == "pong"
  end
end
