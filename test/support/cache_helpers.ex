defmodule WandererKills.Test.CacheHelpers do
  @moduledoc """
  Test helper functions for cache management and testing.

  This module provides utilities for:
  - Cache setup and cleanup
  - Cache state verification
  - Cache operation assertions
  - Test data insertion and retrieval
  """

  import ExUnit.Assertions

  @doc """
  Cleans up any existing processes before tests.
  """
  def cleanup_processes do
    # Clear KillStore ETS tables
    WandererKills.Core.Storage.KillmailStore.clear()

    # Clear the actual wanderer_cache that's running
    safe_clear_cache(:wanderer_cache)

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

    # Give Cachex a moment to settle after clearing
    Process.sleep(10)

    :ok
  end

  @doc """
  Clears only the test-specific cache instances.
  """
  @spec clear_test_caches() :: :ok
  def clear_test_caches do
    # Clear the wanderer_cache which is the actual cache used in the application
    safe_clear_cache(:wanderer_cache)
    :ok
  end

  @doc """
  Clears production cache instances (used when tests run against production caches).
  """
  @spec clear_production_caches() :: :ok
  def clear_production_caches do
    safe_clear_cache(:wanderer_cache)
    :ok
  end

  @doc """
  Clears additional caches that may be used in some tests.
  """
  @spec clear_additional_caches() :: :ok
  def clear_additional_caches do
    safe_clear_cache(:active_systems_cache)

    # Clear namespace-specific caches from CacheHelpers
    additional_cache_names = [
      :esi,
      :ship_types,
      :systems,
      :killmails,
      :characters,
      :corporations,
      :alliances
    ]

    Enum.each(additional_cache_names, &safe_clear_cache/1)
    :ok
  end

  # Private helper function that safely clears a cache, ignoring errors
  @spec safe_clear_cache(atom()) :: :ok
  defp safe_clear_cache(cache_name) do
    # Get the configured cache adapter
    adapter = Application.get_env(:wanderer_kills, :cache_adapter, Cachex)

    case adapter.clear(cache_name) do
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

  @doc """
  Sets up cache entries for testing.

  ## Parameters
  - `cache_name` - The cache namespace to use
  - `entries` - A list of {key, value} tuples to insert

  ## Examples

      setup_cache_entries(:ship_types, [
        {"ship_type:123", %{name: "Rifter"}},
        {"ship_type:456", %{name: "Crow"}}
      ])
  """
  @spec setup_cache_entries(atom(), [{String.t(), term()}]) :: :ok
  def setup_cache_entries(cache_name, entries) when is_list(entries) do
    adapter = Application.get_env(:wanderer_kills, :cache_adapter, Cachex)

    Enum.each(entries, fn {key, value} ->
      adapter.put(cache_name, key, value, [])
    end)

    :ok
  end

  @doc """
  Gets a value from cache for testing assertions.
  """
  @spec get_cache_value(atom(), String.t()) :: {:ok, term()} | {:error, term()}
  def get_cache_value(cache_name, key) do
    adapter = Application.get_env(:wanderer_kills, :cache_adapter, Cachex)

    case adapter.get(cache_name, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Checks if a cache entry exists.
  """
  @spec cache_exists?(atom(), String.t()) :: boolean()
  def cache_exists?(cache_name, key) do
    adapter = Application.get_env(:wanderer_kills, :cache_adapter, Cachex)

    case adapter.exists?(cache_name, key) do
      {:ok, exists?} -> exists?
      {:error, _} -> false
    end
  end

  @doc """
  Gets the size of a cache for testing assertions.
  """
  @spec cache_size(atom()) :: {:ok, non_neg_integer()} | {:error, term()}
  def cache_size(cache_name) do
    adapter = Application.get_env(:wanderer_kills, :cache_adapter, Cachex)

    case adapter.size(cache_name) do
      {:ok, size} -> {:ok, size}
      error -> error
    end
  end

  @doc """
  Verifies cache state matches expected values.

  ## Parameters
  - `cache_name` - The cache namespace to check
  - `expected` - A map of key => value pairs that should exist

  Returns `:ok` if all expected entries exist with correct values,
  or `{:error, details}` if there are mismatches.
  """
  @spec verify_cache_state(atom(), %{String.t() => term()}) :: :ok | {:error, term()}
  def verify_cache_state(cache_name, expected) when is_map(expected) do
    mismatches =
      Enum.reduce(expected, [], fn {key, expected_value}, acc ->
        case get_cache_value(cache_name, key) do
          {:ok, ^expected_value} ->
            acc

          {:ok, actual_value} ->
            [{:value_mismatch, key, expected_value, actual_value} | acc]

          {:error, :not_found} ->
            [{:missing_key, key, expected_value} | acc]

          {:error, reason} ->
            [{:cache_error, key, reason} | acc]
        end
      end)

    case mismatches do
      [] -> :ok
      mismatches -> {:error, mismatches}
    end
  end

  @doc """
  Cleans up KillStore data for testing.
  """
  @spec stop_killmail_store() :: :ok
  def stop_killmail_store do
    WandererKills.Core.Storage.KillmailStore.clear()
    :ok
  end
end
