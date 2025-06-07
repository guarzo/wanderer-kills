defmodule WandererKills.Test.CacheHelpers do
  @moduledoc """
  Test helpers for cache operations during testing.

  This module provides utilities for setting up and tearing down
  cache state during tests, using Cachex instead of ETS.
  """

  @doc """
  Clears all cache namespaces.

  This should be called in test setup or teardown to ensure
  clean state between tests.
  """
  @spec clear_all_caches() :: :ok
  def clear_all_caches do
    cache_names = [
      :esi,
      :ship_types,
      :systems,
      :killmails,
      :characters,
      :corporations,
      :alliances
    ]

    Enum.each(cache_names, fn cache_name ->
      case Cachex.clear(cache_name) do
        {:ok, _} ->
          :ok

        # Cache doesn't exist, that's fine
        {:error, :no_cache} ->
          :ok

        {:error, reason} ->
          # Log but don't fail - this is just test cleanup
          require Logger

          Logger.warning("Failed to clear cache during test cleanup",
            cache: cache_name,
            reason: inspect(reason)
          )
      end
    end)

    :ok
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
    Enum.each(entries, fn {key, value} ->
      Cachex.put(cache_name, key, value)
    end)

    :ok
  end

  @doc """
  Gets a value from cache for testing assertions.
  """
  @spec get_cache_value(atom(), String.t()) :: {:ok, term()} | {:error, term()}
  def get_cache_value(cache_name, key) do
    case Cachex.get(cache_name, key) do
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
    case Cachex.exists?(cache_name, key) do
      {:ok, exists?} -> exists?
      {:error, _} -> false
    end
  end

  @doc """
  Gets the size of a cache for testing assertions.
  """
  @spec cache_size(atom()) :: {:ok, non_neg_integer()} | {:error, term()}
  def cache_size(cache_name) do
    case Cachex.size(cache_name) do
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
end
