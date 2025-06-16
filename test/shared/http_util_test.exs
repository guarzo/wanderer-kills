defmodule WandererKills.Ingest.Http.UtilTest do
  use ExUnit.Case, async: false

  alias WandererKills.Ingest.Http.Client

  setup do
    WandererKills.TestHelpers.setup_mocks()
    :ok
  end

  describe "handle_status_code/2" do
    test "handles success responses" do
      result = Client.handle_status_code(200, %{"test" => "data"})
      assert {:ok, %{"test" => "data"}} = result
    end

    test "handles not found responses" do
      result = Client.handle_status_code(404, %{})
      assert {:error, :not_found} = result
    end

    test "handles rate limited responses" do
      result = Client.handle_status_code(429, %{})
      assert {:error, :rate_limited} = result
    end

    test "handles other error responses" do
      result = Client.handle_status_code(500, %{})
      assert {:error, _} = result
    end
  end
end
