defmodule WandererKills.Test.DataHelpers do
  @moduledoc """
  Test helper functions for generating test data.

  This module provides utilities for:
  - Test data generation for various entity types
  - Random ID generation
  - ESI and ZKB response mocking
  - Test data factories
  """

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
end
