defmodule WandererKills.TestHelpers do
  @moduledoc """
  Test helper functions for the WandererKills application.

  This module provides common functionality used across test files,
  including cache management, setup utilities, and assertions.

  ## Features

  - Unified cache clearing functionality
  - Test data factories
  - Common assertions
  - Test environment setup

  ## Usage

  ```elixir
  defmodule MyTest do
    use ExUnit.Case
    import WandererKills.TestHelpers

    setup do
      clear_all_caches()
      :ok
    end
  end
  ```
  """

  @doc """
  Cleans up any existing processes before tests.
  """
  def cleanup_processes do
    # Stop KillmailStore if it's running
    if pid = Process.whereis(WandererKills.KillmailStore) do
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

  This function clears both test-specific and production cache instances
  to ensure tests start with a clean state.

  ## Cache Types Cleared

  - Test caches (when running in test environment)
  - Production caches (when available)
  - Active systems cache

  ## Example

  ```elixir
  setup do
    WandererKills.TestHelpers.clear_all_caches()
    :ok
  end
  ```
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
    safe_clear_cache(:wanderer_test_killmails_cache)
    safe_clear_cache(:wanderer_test_system_cache)
    safe_clear_cache(:wanderer_test_esi_cache)
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
  Sets up default mocks for HTTP client and other services.
  This function ensures backward compatibility with existing tests.
  """
  @spec setup_mocks() :: :ok
  def setup_mocks do
    WandererKills.Http.Client.Mock
    |> Mox.stub(:get_with_rate_limit, &mock_http_response/2)
    |> Mox.stub(:handle_status_code, fn
      200, %{body: body} -> {:ok, body}
      200, response -> {:ok, response}
      404, _response -> {:error, :not_found}
      429, _response -> {:error, :rate_limited}
      status, _response -> {:error, "HTTP #{status}"}
    end)

    :ok
  end

  # Private helper function for HTTP response mocking
  defp mock_http_response("https://esi.evetech.net/latest/characters/" <> _id, _opts) do
    character_data = %{
      "character_id" => 123,
      "name" => "Test Character",
      "corporation_id" => 456,
      "alliance_id" => 789,
      "faction_id" => nil,
      "security_status" => 5.0
    }

    {:ok, %{status: 200, body: character_data}}
  end

  defp mock_http_response("https://esi.evetech.net/latest/corporations/" <> _id, _opts) do
    corp_data = %{
      "corporation_id" => 456,
      "name" => "Test Corp",
      "alliance_id" => 789,
      "faction_id" => nil,
      "ticker" => "TEST",
      "member_count" => 100,
      "ceo_id" => 123
    }

    {:ok, %{status: 200, body: corp_data}}
  end

  defp mock_http_response("https://esi.evetech.net/latest/alliances/" <> _id, _opts) do
    alliance_data = %{
      "alliance_id" => 789,
      "name" => "Test Alliance",
      "ticker" => "TEST",
      "creator_corporation_id" => 456,
      "creator_id" => 123,
      "date_founded" => "2024-01-01T00:00:00Z",
      "executor_corporation_id" => 456
    }

    {:ok, %{status: 200, body: alliance_data}}
  end

  defp mock_http_response("https://esi.evetech.net/latest/universe/types/" <> _id, _opts) do
    type_data = %{
      "type_id" => 123,
      "name" => "Test Type",
      "description" => "A test type",
      "group_id" => 456,
      "market_group_id" => 789,
      "mass" => 1000.0,
      "packaged_volume" => 500.0,
      "portion_size" => 1,
      "published" => true,
      "radius" => 50.0,
      "volume" => 1000.0
    }

    {:ok, %{status: 200, body: type_data}}
  end

  defp mock_http_response("https://esi.evetech.net/latest/universe/groups/" <> _id, _opts) do
    group_data = %{
      "group_id" => 456,
      "name" => "Test Group",
      "category_id" => 789,
      "published" => true,
      "types" => [123, 124]
    }

    {:ok, %{status: 200, body: group_data}}
  end

  defp mock_http_response(_url, _opts) do
    {:error, :not_found}
  end

  @doc """
  Creates a test killmail with the given ID.
  """
  def create_test_killmail(killmail_id) do
    %{
      "killmail_id" => killmail_id,
      "killID" => killmail_id,
      "killTime" => "2024-01-01T00:00:00Z",
      "solarSystemID" => 30_000_142,
      "victim" => %{
        "characterID" => 12_345,
        "corporationID" => 67_890,
        "allianceID" => 54_321,
        "shipTypeID" => 1234
      },
      "attackers" => [
        %{
          "characterID" => 11_111,
          "corporationID" => 22_222,
          "allianceID" => 33_333,
          "shipTypeID" => 5678,
          "finalBlow" => true
        }
      ],
      "zkb" => %{
        "locationID" => 50_000_001,
        "hash" => "abc123",
        "fittedValue" => 1_000_000.0,
        "totalValue" => 1_500_000.0,
        "points" => 1,
        "npc" => false,
        "solo" => true,
        "awox" => false
      }
    }
  end

  @doc """
  Creates test ESI data for characters, corporations, etc.

  ## Parameters
  - `type` - The type of ESI data (:character, :corporation, :alliance, :type)
  - `id` - The ID for the entity
  - `opts` - Additional options

  ## Example

  ```elixir
  character = create_test_esi_data(:character, 12345, name: "Test Character")
  ```
  """
  @spec create_test_esi_data(atom(), integer(), keyword()) :: map()
  def create_test_esi_data(type, id, opts \\ [])

  def create_test_esi_data(:character, character_id, opts) do
    %{
      character_id: character_id,
      name: Keyword.get(opts, :name, "Test Character #{character_id}"),
      corporation_id: Keyword.get(opts, :corporation_id, 1_000_001),
      alliance_id: Keyword.get(opts, :alliance_id, 2_000_001),
      faction_id: Keyword.get(opts, :faction_id, nil),
      security_status: Keyword.get(opts, :security_status, 0.0)
    }
  end

  def create_test_esi_data(:corporation, corporation_id, opts) do
    %{
      corporation_id: corporation_id,
      name: Keyword.get(opts, :name, "Test Corp #{corporation_id}"),
      ticker: Keyword.get(opts, :ticker, "TEST"),
      alliance_id: Keyword.get(opts, :alliance_id, 2_000_001),
      member_count: Keyword.get(opts, :member_count, 100),
      ceo_id: Keyword.get(opts, :ceo_id, 12_345)
    }
  end

  def create_test_esi_data(:alliance, alliance_id, opts) do
    %{
      alliance_id: alliance_id,
      name: Keyword.get(opts, :name, "Test Alliance #{alliance_id}"),
      ticker: Keyword.get(opts, :ticker, "TESTA"),
      creator_corporation_id: Keyword.get(opts, :creator_corporation_id, 1_000_001),
      creator_id: Keyword.get(opts, :creator_id, 12_345)
    }
  end

  def create_test_esi_data(:type, type_id, opts) do
    %{
      type_id: type_id,
      name: Keyword.get(opts, :name, "Test Type #{type_id}"),
      group_id: Keyword.get(opts, :group_id, 25),
      published: Keyword.get(opts, :published, true)
    }
  end

  @doc """
  Stops the KillmailStore process if it's running.
  """
  def stop_killmail_store do
    if pid = Process.whereis(WandererKills.KillmailStore) do
      Process.exit(pid, :normal)
      # Give it time to shut down
      :timer.sleep(10)
    end
  end
end
