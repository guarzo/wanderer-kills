defmodule WandererKills.Http.UtilTest do
  use ExUnit.Case, async: true

  alias WandererKills.Core.Http

  setup do
    WandererKills.TestHelpers.setup_mocks()
    :ok
  end

  describe "retriable_error?/1" do
    test "returns true for retriable errors" do
      assert Http.retriable_error?(:timeout)
      assert Http.retriable_error?(:rate_limited)
    end

    test "returns false for non-retriable errors" do
      refute Http.retriable_error?(:not_found)
      refute Http.retriable_error?(:invalid_format)
    end
  end

  describe "handle_status_code/2" do
    test "handles success responses" do
      result = Http.handle_status_code(200, %{"test" => "data"})
      assert {:ok, %{"test" => "data"}} = result
    end

    test "handles not found responses" do
      result = Http.handle_status_code(404, %{})
      assert {:error, :not_found} = result
    end

    test "handles rate limited responses" do
      result = Http.handle_status_code(429, %{})
      assert {:error, :rate_limited} = result
    end

    test "handles other error responses" do
      result = Http.handle_status_code(500, %{})
      assert {:error, _} = result
    end
  end
end
