defmodule WandererKills.TestHelpers do
  @moduledoc """
  Unified test helper interface for the WandererKills application.

  This module provides a single import point for all test helpers while
  delegating to domain-specific helper modules for better organization.

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

  ## Domain-specific helpers

  For more specific functionality, you can also import the domain helpers directly:

  - `WandererKills.Test.CacheHelpers` - Cache management and testing
  - `WandererKills.Test.HttpHelpers` - HTTP mocking and testing
  - `WandererKills.Test.DataHelpers` - Test data generation
  """

  # Re-export commonly used functions for convenience
  defdelegate clear_all_caches(), to: WandererKills.Test.CacheHelpers
  defdelegate setup_mocks(), to: WandererKills.Test.HttpHelpers
  defdelegate generate_test_data(type, id \\ nil), to: WandererKills.Test.DataHelpers
  defdelegate random_system_id(), to: WandererKills.Test.DataHelpers
  defdelegate random_character_id(), to: WandererKills.Test.DataHelpers
  defdelegate random_killmail_id(), to: WandererKills.Test.DataHelpers

  # Aliases for commonly misnamed functions
  defdelegate setup_http_mocks(), to: WandererKills.Test.HttpHelpers, as: :setup_mocks

  @doc """
  Creates a test killmail with the given ID.
  """
  def create_test_killmail(id) do
    WandererKills.Test.DataHelpers.generate_test_data(:killmail, id)
  end

  @doc """
  Convenience function to set up a clean test environment.

  This function combines the most common setup operations:
  - Clears all caches
  - Sets up HTTP mocks
  - Cleans up any existing processes
  """
  def setup_test_environment do
    cleanup_processes()
    clear_all_caches()
    setup_mocks()
    :ok
  end

  @doc """
  Cleanup any test processes that might be running.
  """
  def cleanup_processes do
    # Add any process cleanup logic here if needed
    :ok
  end
end
