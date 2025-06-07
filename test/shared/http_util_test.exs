defmodule WandererKills.Http.UtilTest do
  use ExUnit.Case, async: true

  alias WandererKills.Http.Utils, as: Util
  alias WandererKills.Retry
  alias WandererKills.Http.Errors.TimeoutError

  setup do
    WandererKills.TestHelpers.setup_mocks()
    :ok
  end

  describe "retriable_error?/1" do
    test "returns true for retriable errors" do
      assert Retry.retriable_error?(%TimeoutError{})
      assert Retry.retriable_error?(:rate_limited)
    end

    test "returns false for non-retriable errors" do
      refute Retry.retriable_error?(:not_found)
      refute Retry.retriable_error?(:invalid_format)
    end
  end

  describe "handle_response/1" do
    test "handles success responses" do
      response = %{status: 200, body: %{"test" => "data"}}

      result = Util.handle_response(response, WandererKills.Http.Client.Mock)

      assert {:ok, %{"test" => "data"}} = result
    end

    test "handles not found responses" do
      response = %{status: 404}

      result = Util.handle_response(response, WandererKills.Http.Client.Mock)

      assert {:error, :not_found} = result
    end

    test "handles rate limited responses" do
      response = %{status: 429}

      result = Util.handle_response(response, WandererKills.Http.Client.Mock)

      assert {:error, :rate_limited} = result
    end

    test "handles other error responses" do
      response = %{status: 500}

      result = Util.handle_response(response, WandererKills.Http.Client.Mock)

      assert {:error, "HTTP 500"} = result
    end
  end
end
