defmodule WandererKills.ApiSmokeTest do
  use ExUnit.Case, async: false
  import Plug.Test

  @opts WandererKills.Web.Api.init([])

  test "GET /ping returns pong" do
    conn = conn(:get, "/ping")
    response = WandererKills.Web.Api.call(conn, @opts)
    assert response.status == 200
    assert response.resp_body == "pong"
  end
end
