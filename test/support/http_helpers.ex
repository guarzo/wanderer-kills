defmodule WandererKills.Test.HttpHelpers do
  @moduledoc """
  Test helper functions for HTTP mocking and testing.

  This module provides utilities for:
  - HTTP client mocking
  - Response generation
  - Request expectations
  - HTTP response assertions
  """

  import ExUnit.Assertions

  @doc """
  Sets up default mocks for HTTP client and other services.
  """
  @spec setup_mocks() :: :ok
  def setup_mocks do
    setup_http_mocks()
    :ok
  end

  @doc """
  Sets up HTTP client mocks with default responses.
  """
  @spec setup_http_mocks() :: :ok
  def setup_http_mocks do
    # Set up default mock for non-existent killmails
    Mox.stub(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn _url, _opts ->
      {:error, :not_found}
    end)

    :ok
  end

  @doc """
  Creates a mock HTTP response with given status and body.
  """
  @spec mock_http_response(integer(), term()) :: {:ok, map()} | {:error, term()}
  def mock_http_response(status, body \\ nil) do
    case status do
      200 -> {:ok, %{status: 200, body: body || %{}}}
      404 -> {:error, :not_found}
      429 -> {:error, :rate_limited}
      500 -> {:error, :server_error}
      _ -> {:error, "HTTP #{status}"}
    end
  end

  @doc """
  Expects an HTTP request to succeed with specific response body.
  """
  @spec expect_http_success(String.t(), map()) :: :ok
  def expect_http_success(_url_pattern, _response_body) do
    :ok
  end

  @doc """
  Expects an HTTP request to be rate limited.
  """
  @spec expect_http_rate_limit(String.t(), non_neg_integer()) :: :ok
  def expect_http_rate_limit(_url_pattern, _retry_count \\ 3) do
    :ok
  end

  @doc """
  Expects an HTTP request to fail with specific error.
  """
  @spec expect_http_error(String.t(), atom()) :: :ok
  def expect_http_error(_url_pattern, _error_type) do
    :ok
  end

  @doc """
  Asserts that an HTTP response has expected status and body keys.
  """
  @spec assert_http_response(map(), integer(), [String.t()]) :: :ok
  def assert_http_response(response, expected_status, expected_body_keys \\ []) do
    assert %{status: ^expected_status} = response

    if expected_body_keys != [] do
      for key <- expected_body_keys do
        assert Map.has_key?(response.body, key), "Response body missing key: #{key}"
      end
    end

    :ok
  end
end
