defmodule WandererKills.CacheTestHelpers do
  @moduledoc """
  Shared test helpers for cache-related functionality.

  This module provides parameterized test functions and common setup utilities
  to reduce duplication across cache tests and improve DRYness.

  ## Features

  - Parameterized cache operation tests
  - Mock data generators
  - Common assertion helpers
  - Setup utilities for cache tests

  ## Usage

  ```elixir
  defmodule MyCacheTest do
    use ExUnit.Case
    import WandererKills.CacheTestHelpers

    test_cache_get_set_operations(Cache, "my_cache", "test_key", "test_value")
  end
  ```
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks
  import Mox

  @doc """
  Tests basic get/set operations for any cache module.

  This parameterized test reduces duplication by testing the common pattern:
  1. Get non-existent key returns nil/empty
  2. Set value
  3. Get returns the set value
  4. Delete removes the value

  ## Parameters
  - `cache_module` - The cache module to test
  - `cache_type` - Type identifier for the cache
  - `key` - Test key to use
  - `value` - Test value to set
  """
  defmacro test_cache_get_set_operations(cache_module, cache_type, key, value) do
    quote do
      describe "#{unquote(cache_type)} basic operations" do
        test "get returns nil for non-existent key" do
          result = unquote(cache_module).get_value(unquote(cache_type), unquote(key))
          assert result == {:ok, nil} or result == {:error, :not_found}
        end

        test "set and get work together" do
          assert :ok =
                   unquote(cache_module).set_value(
                     unquote(cache_type),
                     unquote(key),
                     unquote(value)
                   )

          assert {:ok, unquote(value)} =
                   unquote(cache_module).get_value(unquote(cache_type), unquote(key))
        end

        test "delete removes value" do
          assert :ok =
                   unquote(cache_module).set_value(
                     unquote(cache_type),
                     unquote(key),
                     unquote(value)
                   )

          assert :ok = unquote(cache_module).delete_value(unquote(cache_type), unquote(key))

          result = unquote(cache_module).get_value(unquote(cache_type), unquote(key))
          assert result == {:ok, nil} or result == {:error, :not_found}
        end
      end
    end
  end

  @doc """
  Tests ESI cache operations with mock HTTP responses.

  This parameterized test handles the common pattern for ESI cache testing:
  1. Setup HTTP mock
  2. Call cache function
  3. Verify response structure
  4. Verify caching behavior
  """
  defmacro test_esi_cache_operations(function_name, id_param, mock_response, expected_fields) do
    quote do
      test "#{unquote(function_name)} fetches and caches data" do
        WandererKills.CacheTestHelpers.setup_esi_mock(unquote(mock_response))

        assert {:ok, result} = WandererKills.Esi.Cache.unquote(function_name)(unquote(id_param))

        # Verify all expected fields are present
        for {field, expected_value} <- unquote(expected_fields) do
          assert Map.get(result, field) == expected_value
        end
      end

      test "#{unquote(function_name)} uses cached data on second call" do
        WandererKills.CacheTestHelpers.setup_esi_mock(unquote(mock_response))

        # First call should fetch from HTTP
        assert {:ok, result1} = WandererKills.Esi.Cache.unquote(function_name)(unquote(id_param))

        # Second call should use cache (no additional HTTP expectation needed)
        assert {:ok, result2} = WandererKills.Esi.Cache.unquote(function_name)(unquote(id_param))

        assert result1 == result2
      end
    end
  end

  @doc """
  Generates common test data for different entity types.
  """
  def generate_test_data(entity_type, id \\ nil) do
    base_id = id || :rand.uniform(1_000_000)

    case entity_type do
      :character ->
        %{
          character_id: base_id,
          name: "Test Character #{base_id}",
          corporation_id: base_id + 1000,
          alliance_id: base_id + 2000,
          security_status: 5.0
        }

      :corporation ->
        %{
          corporation_id: base_id,
          name: "Test Corp #{base_id}",
          ticker: "TC#{base_id}",
          member_count: 100,
          ceo_id: base_id + 100
        }

      :alliance ->
        %{
          alliance_id: base_id,
          name: "Test Alliance #{base_id}",
          ticker: "TA#{base_id}",
          creator_corporation_id: base_id + 1000
        }

      :ship_type ->
        %{
          type_id: base_id,
          name: "Test Ship #{base_id}",
          group_id: base_id + 100,
          published: true,
          mass: 1000.0,
          volume: 500.0
        }

      :killmail ->
        %{
          "killmail_id" => base_id,
          "kill_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "solar_system_id" => 30_000_000 + base_id,
          "victim" => %{
            "character_id" => base_id + 1,
            "corporation_id" => base_id + 1000,
            "ship_type_id" => base_id + 2000
          },
          "attackers" => [
            %{
              "character_id" => base_id + 2,
              "corporation_id" => base_id + 1001,
              "final_blow" => true,
              "damage_done" => 1000
            }
          ]
        }
    end
  end

  @doc """
  Sets up ESI HTTP mocks with the provided response data.
  """
  def setup_esi_mock(response_data) do
    expect(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn _url, _opts ->
      {:ok, %{body: response_data}}
    end)
  end

  @doc """
  Sets up standard cache test environment.
  """
  def setup_cache_test do
    WandererKills.TestHelpers.clear_all_caches()
    Application.put_env(:wanderer_kills, :http_client, WandererKills.Http.Client.Mock)

    on_exit(fn ->
      Application.put_env(:wanderer_kills, :http_client, WandererKills.MockHttpClient)
    end)
  end

  @doc """
  Asserts that a cache operation was successful.
  """
  def assert_cache_success(result, expected_value \\ nil) do
    case result do
      :ok when expected_value == nil ->
        :ok

      {:ok, ^expected_value} when expected_value != nil ->
        :ok

      {:ok, actual_value} when expected_value != nil ->
        flunk("Expected #{inspect(expected_value)}, got #{inspect(actual_value)}")

      {:error, reason} ->
        flunk("Cache operation failed: #{inspect(reason)}")

      other ->
        flunk("Unexpected cache result: #{inspect(other)}")
    end
  end

  @doc """
  Asserts that cache operations follow expected patterns for list management.
  """
  def assert_list_operations(cache_module, list_type, container_id, item_id) do
    # Initially empty
    assert {:ok, []} = cache_module.get_list(list_type, container_id)

    # Add item
    assert :ok = cache_module.add_to_list(list_type, container_id, item_id)
    assert {:ok, [^item_id]} = cache_module.get_list(list_type, container_id)

    # Add same item again (should not duplicate)
    assert :ok = cache_module.add_to_list(list_type, container_id, item_id)
    assert {:ok, [^item_id]} = cache_module.get_list(list_type, container_id)

    # Add different item
    other_item = item_id + 1
    assert :ok = cache_module.add_to_list(list_type, container_id, other_item)
    assert {:ok, items} = cache_module.get_list(list_type, container_id)
    assert length(items) == 2
    assert item_id in items
    assert other_item in items
  end

  @doc """
  Asserts that counter operations work correctly.
  """
  def assert_counter_operations(cache_module, counter_type, id) do
    # Initially zero
    assert {:ok, 0} = cache_module.get_count(counter_type, id)

    # Increment
    assert :ok = cache_module.increment_count(counter_type, id)
    assert {:ok, 1} = cache_module.get_count(counter_type, id)

    # Increment again
    assert :ok = cache_module.increment_count(counter_type, id)
    assert {:ok, 2} = cache_module.get_count(counter_type, id)
  end

  @doc """
  Generates a random system ID for testing.
  """
  def random_system_id do
    30_000_000 + :rand.uniform(10_000)
  end

  @doc """
  Generates a random character ID for testing.
  """
  def random_character_id do
    1_000_000 + :rand.uniform(100_000_000)
  end

  @doc """
  Generates a random killmail ID for testing.
  """
  def random_killmail_id do
    :rand.uniform(1_000_000_000)
  end
end
