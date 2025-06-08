defmodule WandererKills.ApiSmokeTest do
  use ExUnit.Case, async: false
  import Plug.Test

  @opts WandererKillsWeb.Api.init([])

  test "GET /ping returns pong" do
    conn = conn(:get, "/ping")
    response = WandererKillsWeb.Api.call(conn, @opts)
    assert response.status == 200
    assert response.resp_body == "pong"
  end
end
