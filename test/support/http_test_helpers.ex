defmodule WandererKills.HttpTestHelpers do
  @moduledoc """
  Shared test helpers for HTTP client and fetcher functionality.

  This module provides parameterized test functions and common utilities
  to reduce duplication across HTTP and fetcher tests.

  ## Features

  - HTTP client mock setup
  - Rate limiting test scenarios
  - Error handling test patterns
  - Response validation utilities

  ## Usage

  ```elixir
  defmodule MyHttpTest do
    use ExUnit.Case
    import WandererKills.HttpTestHelpers

    setup do
      setup_http_mocks()
    end
  end
  ```
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks
  import Mox

  @doc """
  Sets up standard HTTP client mocks for testing.
  """
  def setup_http_mocks do
    Application.put_env(:wanderer_kills, :http_client, WandererKills.Http.Client.Mock)
    Application.put_env(:wanderer_kills, :zkb_client, WandererKills.Zkb.Client.Mock)

    on_exit(fn ->
      Application.put_env(:wanderer_kills, :http_client, WandererKills.Http.Client)
      Application.put_env(:wanderer_kills, :zkb_client, WandererKills.Zkb.Client)
    end)
  end

  @doc """
  Creates a mock HTTP response with the given status and body.
  """
  def mock_http_response(status, body \\ nil) do
    response = %{status: status}
    if body, do: Map.put(response, :body, body), else: response
  end

  @doc """
  Sets up mock expectations for successful HTTP requests.
  """
  def expect_http_success(url_pattern, response_body) do
    expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn url, _opts ->
      if String.contains?(url, url_pattern) do
        {:ok, mock_http_response(200, response_body)}
      else
        {:error, :not_found}
      end
    end)
  end

  @doc """
  Sets up mock expectations for HTTP rate limiting.
  """
  def expect_http_rate_limit(url_pattern, retry_count \\ 3) do
    expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, retry_count, fn url, _opts ->
      if String.contains?(url, url_pattern) do
        {:error, :rate_limited}
      else
        {:error, :not_found}
      end
    end)
  end

  @doc """
  Sets up mock expectations for HTTP errors.
  """
  def expect_http_error(url_pattern, error_type) do
    expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn url, _opts ->
      if String.contains?(url, url_pattern) do
        {:error, error_type}
      else
        {:error, :not_found}
      end
    end)
  end

  @doc """
  Tests common HTTP error scenarios for any HTTP client function.

  This parameterized test reduces duplication by testing standard error patterns:
  1. Rate limiting
  2. Not found
  3. Network errors
  4. Timeout errors
  """
  defmacro test_http_error_scenarios(module, function, args) do
    quote do
      describe "#{unquote(function)} error handling" do
        test "handles rate limiting" do
          WandererKills.HttpTestHelpers.expect_http_rate_limit("test")

          result = apply(unquote(module), unquote(function), unquote(args))
          assert {:error, :rate_limited} = result
        end

        test "handles not found" do
          WandererKills.HttpTestHelpers.expect_http_error("test", :not_found)

          result = apply(unquote(module), unquote(function), unquote(args))
          assert {:error, :not_found} = result
        end

        test "handles network errors" do
          WandererKills.HttpTestHelpers.expect_http_error("test", :timeout)

          result = apply(unquote(module), unquote(function), unquote(args))
          assert {:error, :timeout} = result
        end
      end
    end
  end

  @doc """
  Asserts that an HTTP response has the expected structure.
  """
  def assert_http_response(response, expected_status, expected_body_keys \\ []) do
    case response do
      {:ok, %{status: ^expected_status, body: body}} ->
        for key <- expected_body_keys do
          assert Map.has_key?(body, key), "Response body missing key: #{key}"
        end

        :ok

      {:ok, %{status: actual_status}} ->
        flunk("Expected status #{expected_status}, got #{actual_status}")

      {:error, reason} ->
        flunk("HTTP request failed: #{inspect(reason)}")

      other ->
        flunk("Unexpected HTTP response: #{inspect(other)}")
    end
  end

  @doc """
  Generates test data for ZKB API responses.
  """
  def generate_zkb_response(type, count \\ 1) do
    case type do
      :killmails ->
        for i <- 1..count do
          %{
            "killID" => 1_000_000 + i,
            "zkb" => %{
              "hash" => "test_hash_#{i}",
              "totalValue" => 1_000_000.0 * i,
              "npc" => false
            },
            "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        end

      :system_stats ->
        %{
          "system_id" => 30_000_142,
          "kills_last_hour" => count,
          "jumps_last_hour" => count * 10
        }
    end
  end

  @doc """
  Generates test data for ESI API responses.
  """
  def generate_esi_response(type, id) do
    case type do
      :character ->
        %{
          "character_id" => id,
          "name" => "Test Character #{id}",
          "corporation_id" => id + 1000,
          "alliance_id" => id + 2000,
          "security_status" => 5.0
        }

      :corporation ->
        %{
          "corporation_id" => id,
          "name" => "Test Corp #{id}",
          "ticker" => "TC#{id}",
          "member_count" => 100,
          "ceo_id" => id + 100
        }

      :alliance ->
        %{
          "alliance_id" => id,
          "name" => "Test Alliance #{id}",
          "ticker" => "TA#{id}",
          "creator_corporation_id" => id + 1000
        }

      :ship_type ->
        %{
          "type_id" => id,
          "name" => "Test Ship #{id}",
          "group_id" => id + 100,
          "published" => true,
          "mass" => 1000.0,
          "volume" => 500.0
        }

      :killmail ->
        %{
          "killmail_id" => id,
          "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "solar_system_id" => 30_000_142,
          "victim" => %{
            "character_id" => id + 1,
            "corporation_id" => id + 1000,
            "ship_type_id" => id + 2000,
            "damage_taken" => 5000
          },
          "attackers" => [
            %{
              "character_id" => id + 2,
              "corporation_id" => id + 1001,
              "final_blow" => true,
              "damage_done" => 5000,
              "ship_type_id" => id + 3000
            }
          ]
        }
    end
  end

  @doc """
  Tests fetcher operations with various scenarios.

  This parameterized test reduces duplication across fetcher tests.
  """
  defmacro test_fetcher_scenarios(module, function, base_args) do
    quote do
      describe "#{unquote(function)} scenarios" do
        test "handles successful fetch" do
          WandererKills.HttpTestHelpers.expect_http_success("test", %{"data" => "test"})

          result = apply(unquote(module), unquote(function), unquote(base_args))
          assert {:ok, _} = result
        end

        test "handles empty response" do
          WandererKills.HttpTestHelpers.expect_http_success("test", [])

          result = apply(unquote(module), unquote(function), unquote(base_args))
          assert {:ok, []} = result or {:error, _} = result
        end

        test "handles API errors" do
          WandererKills.HttpTestHelpers.expect_http_error("test", :api_error)

          result = apply(unquote(module), unquote(function), unquote(base_args))
          assert {:error, _} = result
        end
      end
    end
  end

  @doc """
  Asserts that a fetcher result has the expected structure.
  """
  def assert_fetcher_result(result, expected_type) do
    case {result, expected_type} do
      {{:ok, items}, :list} when is_list(items) ->
        :ok

      {{:ok, item}, :single} when is_map(item) ->
        :ok

      {{:ok, count}, :count} when is_integer(count) ->
        :ok

      {{:error, _reason}, :error} ->
        :ok

      {actual, expected} ->
        flunk("Expected #{expected} result, got: #{inspect(actual)}")
    end
  end

  @doc """
  Sets up mock expectations for batch operations.
  """
  def expect_batch_responses(url_responses) do
    for {url_pattern, response} <- url_responses do
      expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn url, _opts ->
        if String.contains?(url, url_pattern) do
          {:ok, mock_http_response(200, response)}
        else
          {:error, :not_found}
        end
      end)
    end
  end
end
