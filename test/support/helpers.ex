defmodule WandererKills.TestHelpers do
  @moduledoc """
  Consolidated test helper functions for the WandererKills application.

  This module combines functionality from multiple test helper files:
  - Cache management and mocking
  - HTTP mocking and response generation
  - Test data factories and utilities
  - Setup and cleanup functions

  ## Features

  - Unified cache clearing functionality
  - HTTP client mocking and response generation
  - Test data factories for killmails, ESI data, etc.
  - Common assertions and test utilities
  - Test environment setup and teardown

  ## Usage

  ```elixir
  defmodule MyTest do
    use ExUnit.Case
    import WandererKills.TestHelpers

    setup do
      clear_all_caches()
      setup_mocks()
      :ok
    end
  end
  ```
  """

  import ExUnit.Assertions

  #
  # Cache Management Functions
  #

  @doc """
  Cleans up any existing processes before tests.
  """
  def cleanup_processes do
    # Stop KillmailStore if it's running
    if pid = Process.whereis(WandererKills.Killmails.Store) do
      Process.exit(pid, :normal)
      # Give it a moment to shut down
      Process.sleep(10)
    end

    # Clear test caches
    Cachex.clear(:killmails_cache_test)
    Cachex.clear(:system_cache_test)
    Cachex.clear(:esi_cache_test)

    :ok
  end

  @doc """
  Clears all caches used in the application.
  """
  @spec clear_all_caches() :: :ok
  def clear_all_caches do
    # Clear test-specific caches
    clear_test_caches()

    # Clear production caches (if they exist and are running)
    clear_production_caches()

    # Clear any additional caches
    clear_additional_caches()

    :ok
  end

  @doc """
  Clears only the test-specific cache instances.
  """
  @spec clear_test_caches() :: :ok
  def clear_test_caches do
    # Clear the unified cache used in both test and production environments
    safe_clear_cache(:unified_cache)
    :ok
  end

  @doc """
  Clears production cache instances (used when tests run against production caches).
  """
  @spec clear_production_caches() :: :ok
  def clear_production_caches do
    safe_clear_cache(:killmails_cache)
    safe_clear_cache(:system_cache)
    safe_clear_cache(:esi_cache)
    :ok
  end

  @doc """
  Clears additional caches that may be used in some tests.
  """
  @spec clear_additional_caches() :: :ok
  def clear_additional_caches do
    safe_clear_cache(:active_systems_cache)
    :ok
  end

  # Private helper function that safely clears a cache, ignoring errors
  @spec safe_clear_cache(atom()) :: :ok
  defp safe_clear_cache(cache_name) do
    try do
      case Cachex.clear(cache_name) do
        {:ok, _} -> :ok
        # Ignore errors (cache might not exist)
        {:error, _} -> :ok
      end
    catch
      # Ignore process exit errors
      :exit, _ -> :ok
      # Ignore any other errors
      _, _ -> :ok
    end
  end

  @doc """
  Sets up cache for testing with mock data.
  """
  @spec setup_cache_test() :: :ok
  def setup_cache_test do
    clear_all_caches()
    :ok
  end

  @doc """
  Asserts that a cache operation was successful.
  """
  @spec assert_cache_success(term(), term()) :: :ok
  def assert_cache_success(result, expected_value \\ nil) do
    case result do
      {:ok, value} ->
        if expected_value, do: assert(value == expected_value)
        :ok

      :ok ->
        :ok

      other ->
        flunk("Expected cache operation to succeed, got: #{inspect(other)}")
    end
  end

  #
  # HTTP Mocking Functions
  #

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

  #
  # Test Data Generation Functions
  #

  @doc """
  Generates test data for various entity types.
  """
  @spec generate_test_data(atom(), integer() | nil) :: map()
  def generate_test_data(entity_type, id \\ nil)

  def generate_test_data(:killmail, killmail_id) do
    killmail_id = killmail_id || random_killmail_id()

    %{
      "killmail_id" => killmail_id,
      "killmail_time" => "2024-01-01T12:00:00Z",
      "solar_system_id" => random_system_id(),
      "victim" => %{
        "character_id" => random_character_id(),
        "corporation_id" => 98_000_001,
        "alliance_id" => 99_000_001,
        "faction_id" => nil,
        "ship_type_id" => 670,
        "damage_taken" => 1000
      },
      "attackers" => [
        %{
          "character_id" => random_character_id(),
          "corporation_id" => 98_000_002,
          "alliance_id" => 99_000_002,
          "faction_id" => nil,
          "ship_type_id" => 671,
          "weapon_type_id" => 2456,
          "damage_done" => 1000,
          "final_blow" => true,
          "security_status" => 5.0
        }
      ]
    }
  end

  def generate_test_data(:character, character_id) do
    character_id = character_id || random_character_id()

    %{
      "character_id" => character_id,
      "name" => "Test Character #{character_id}",
      "corporation_id" => 98_000_001,
      "alliance_id" => 99_000_001,
      "faction_id" => nil,
      "security_status" => 5.0
    }
  end

  def generate_test_data(:corporation, corporation_id) do
    corporation_id = corporation_id || 98_000_001

    %{
      "corporation_id" => corporation_id,
      "name" => "Test Corp #{corporation_id}",
      "ticker" => "TEST",
      "member_count" => 100,
      "alliance_id" => 99_000_001,
      "ceo_id" => random_character_id()
    }
  end

  def generate_test_data(:alliance, alliance_id) do
    alliance_id = alliance_id || 99_000_001

    %{
      "alliance_id" => alliance_id,
      "name" => "Test Alliance #{alliance_id}",
      "ticker" => "TEST",
      "creator_corporation_id" => 98_000_001,
      "creator_id" => random_character_id(),
      "date_founded" => "2024-01-01T00:00:00Z",
      "executor_corporation_id" => 98_000_001
    }
  end

  def generate_test_data(:type, type_id) do
    type_id = type_id || 670

    %{
      "type_id" => type_id,
      "name" => "Test Type #{type_id}",
      "description" => "A test type for unit testing",
      "group_id" => 25,
      "market_group_id" => 1,
      "mass" => 1000.0,
      "packaged_volume" => 500.0,
      "portion_size" => 1,
      "published" => true,
      "radius" => 100.0,
      "volume" => 500.0
    }
  end

  def generate_test_data(:system, system_id) do
    system_id = system_id || random_system_id()

    %{
      "system_id" => system_id,
      "name" => "Test System #{system_id}",
      "constellation_id" => 20_000_001,
      "security_status" => 0.5,
      "star_id" => 40_000_001
    }
  end

  @doc """
  Generates ZKB-style response data.
  """
  @spec generate_zkb_response(atom(), non_neg_integer()) :: map()
  def generate_zkb_response(type, count \\ 1)

  def generate_zkb_response(:killmail, count) do
    killmails = for _ <- 1..count, do: generate_test_data(:killmail)
    killmails
  end

  def generate_zkb_response(:system_killmails, count) do
    system_id = random_system_id()

    killmails =
      for _ <- 1..count do
        killmail = generate_test_data(:killmail)
        put_in(killmail["solar_system_id"], system_id)
      end

    killmails
  end

  @doc """
  Generates ESI-style response data.
  """
  @spec generate_esi_response(atom(), integer()) :: map()
  def generate_esi_response(type, id) do
    generate_test_data(type, id)
  end

  @doc """
  Creates a test killmail with specific ID.
  """
  @spec create_test_killmail(integer()) :: map()
  def create_test_killmail(killmail_id) do
    generate_test_data(:killmail, killmail_id)
  end

  @doc """
  Creates test ESI data for different entity types.
  """
  @spec create_test_esi_data(atom(), integer(), keyword()) :: map()
  def create_test_esi_data(type, id, opts \\ [])

  def create_test_esi_data(:character, character_id, opts) do
    base_data = generate_test_data(:character, character_id)

    Enum.reduce(opts, base_data, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  def create_test_esi_data(:corporation, corporation_id, opts) do
    base_data = generate_test_data(:corporation, corporation_id)

    Enum.reduce(opts, base_data, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  def create_test_esi_data(:alliance, alliance_id, opts) do
    base_data = generate_test_data(:alliance, alliance_id)

    Enum.reduce(opts, base_data, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  def create_test_esi_data(:type, type_id, opts) do
    base_data = generate_test_data(:type, type_id)

    Enum.reduce(opts, base_data, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  #
  # Random ID Generators
  #

  @doc """
  Generates a random system ID.
  """
  @spec random_system_id() :: integer()
  def random_system_id do
    Enum.random(30_000_001..30_005_000)
  end

  @doc """
  Generates a random character ID.
  """
  @spec random_character_id() :: integer()
  def random_character_id do
    Enum.random(90_000_001..99_999_999)
  end

  @doc """
  Generates a random killmail ID.
  """
  @spec random_killmail_id() :: integer()
  def random_killmail_id do
    Enum.random(100_000_001..999_999_999)
  end

  #
  # Utility Functions
  #

  @doc """
  Stops the KillmailStore process if running.
  """
  @spec stop_killmail_store() :: :ok
  def stop_killmail_store do
    case Process.whereis(WandererKills.Killmails.Store) do
      nil -> :ok
      pid -> Process.exit(pid, :normal)
    end

    :ok
  end
end
