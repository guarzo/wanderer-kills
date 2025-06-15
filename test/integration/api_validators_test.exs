defmodule WandererKills.Api.ValidatorsTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias WandererKillsWeb.Api.Validators
  alias WandererKills.Core.Support.Error

  describe "parse_integer_param/2" do
    test "returns {:ok, integer} for valid integer string" do
      conn = conn(:get, "/test?id=123") |> fetch_query_params()
      assert {:ok, 123} = Validators.parse_integer_param(conn, "id")
    end

    test "returns {:ok, integer} for valid integer string with leading zeros" do
      conn = conn(:get, "/test?id=000123") |> fetch_query_params()
      assert {:ok, 123} = Validators.parse_integer_param(conn, "id")
    end

    test "returns {:error, %Error{}} for non-integer string" do
      conn = conn(:get, "/test?id=abc") |> fetch_query_params()
      assert {:error, %Error{type: :invalid_id}} = Validators.parse_integer_param(conn, "id")
    end

    test "returns {:error, %Error{}} for empty string" do
      conn = conn(:get, "/test?id=") |> fetch_query_params()
      assert {:error, %Error{type: :invalid_id}} = Validators.parse_integer_param(conn, "id")
    end

    test "returns {:error, %Error{}} for missing parameter" do
      conn = conn(:get, "/test") |> fetch_query_params()
      assert {:error, %Error{type: :invalid_id}} = Validators.parse_integer_param(conn, "id")
    end

    test "returns {:error, %Error{}} for integer with trailing characters" do
      conn = conn(:get, "/test?id=123abc") |> fetch_query_params()
      assert {:error, %Error{type: :invalid_id}} = Validators.parse_integer_param(conn, "id")
    end

    test "returns {:ok, integer} for negative integer" do
      conn = conn(:get, "/test?id=-123") |> fetch_query_params()
      assert {:ok, -123} = Validators.parse_integer_param(conn, "id")
    end

    test "works with path parameters" do
      conn = %Plug.Conn{params: %{"id" => "456"}}
      assert {:ok, 456} = Validators.parse_integer_param(conn, "id")
    end

    test "returns {:error, %Error{}} for non-ASCII strings" do
      conn = conn(:get, "/test?id=café") |> fetch_query_params()
      assert {:error, %Error{type: :invalid_id}} = Validators.parse_integer_param(conn, "id")
    end

    test "returns {:error, %Error{}} for unicode strings" do
      conn = conn(:get, "/test?id=🚀") |> fetch_query_params()
      assert {:error, %Error{type: :invalid_id}} = Validators.parse_integer_param(conn, "id")
    end

    test "returns {:error, %Error{}} for mixed ASCII and numbers" do
      conn = conn(:get, "/test?id=1２３") |> fetch_query_params()
      assert {:error, %Error{type: :invalid_id}} = Validators.parse_integer_param(conn, "id")
    end

    test "handles non-binary parameter types gracefully" do
      # Simulate a non-binary parameter (though Plug typically ensures strings)
      conn = %Plug.Conn{params: %{"id" => 123}}
      assert {:ok, 123} = Validators.parse_integer_param(conn, "id")
    end

    test "handles nil parameter value" do
      conn = %Plug.Conn{params: %{"id" => nil}}
      assert {:error, %Error{type: :invalid_id}} = Validators.parse_integer_param(conn, "id")
    end

    test "handles atom parameter value" do
      conn = %Plug.Conn{params: %{"id" => :atom_value}}
      assert {:error, %Error{type: :invalid_id}} = Validators.parse_integer_param(conn, "id")
    end
  end

  describe "send_json_resp/3" do
    test "sends JSON response with correct content type and status" do
      conn = conn(:get, "/test")
      data = %{message: "hello", status: "success"}

      result = Validators.send_json_resp(conn, 200, data)

      assert result.status == 200
      assert result.resp_body == Jason.encode!(data)
      assert ["application/json; charset=utf-8"] = get_resp_header(result, "content-type")
    end

    test "sends error JSON response" do
      conn = conn(:get, "/test")
      error_data = %{error: "Not found", code: 404}

      result = Validators.send_json_resp(conn, 404, error_data)

      assert result.status == 404
      assert result.resp_body == Jason.encode!(error_data)
      assert ["application/json; charset=utf-8"] = get_resp_header(result, "content-type")
    end

    test "handles complex nested data structures" do
      conn = conn(:get, "/test")

      complex_data = %{
        killmails: [
          %{id: 123, victim: %{ship_id: 456}, attackers: [%{char_id: 789}]},
          %{id: 124, victim: %{ship_id: 457}, attackers: [%{char_id: 790}]}
        ],
        meta: %{total: 2, page: 1}
      }

      result = Validators.send_json_resp(conn, 200, complex_data)

      assert result.status == 200
      assert result.resp_body == Jason.encode!(complex_data)
      assert ["application/json; charset=utf-8"] = get_resp_header(result, "content-type")
    end
  end
end
