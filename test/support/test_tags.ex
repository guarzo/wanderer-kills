defmodule WandererKills.Test.Tags do
  @moduledoc """
  Centralized ExUnit tag definitions for consistent test organization.
  
  This module provides macros and functions for applying consistent
  tags across the test suite, making it easier to run specific
  test subsets and organize tests by category.
  
  ## Usage
  
  ```elixir
  defmodule MyTest do
    use ExUnit.Case
    use WandererKills.Test.Tags
    
    @moduletag :unit
    @moduletag area: :cache
    @moduletag performance: :fast
  end
  ```
  
  ## Available Tags
  
  ### Test Types
  - `:unit` - Unit tests (fast, isolated)
  - `:integration` - Integration tests (slower, multiple components)
  - `:external` - Tests that hit external APIs
  - `:slow` - Tests that take longer to run
  
  ### Areas
  - `area: :cache` - Cache-related tests
  - `area: :api` - API endpoint tests
  - `area: :killmail_processing` - Killmail processing tests
  - `area: :websocket` - WebSocket-related tests
  - `area: :esi` - ESI integration tests
  - `area: :zkb` - ZKillboard integration tests
  
  ### Performance
  - `performance: :fast` - Tests that complete quickly (< 100ms)
  - `performance: :medium` - Tests that take moderate time (100ms - 1s)
  - `performance: :slow` - Tests that take longer (> 1s)
  
  ### Reliability
  - `flaky: true` - Tests that may occasionally fail due to timing/external factors
  - `skip: true` - Tests that should be skipped
  """
  
  defmacro __using__(_opts) do
    quote do
      import WandererKills.Test.Tags
    end
  end
  
  @doc """
  Applies standard unit test tags.
  """
  defmacro unit_test_tags do
    quote do
      @moduletag :unit
      @moduletag performance: :fast
    end
  end
  
  @doc """
  Applies standard integration test tags.
  """
  defmacro integration_test_tags do
    quote do
      @moduletag :integration
      @moduletag performance: :medium
      @moduletag timeout: 10_000
    end
  end
  
  @doc """
  Applies standard external API test tags.
  """
  defmacro external_test_tags do
    quote do
      @moduletag :external
      @moduletag :integration
      @moduletag performance: :slow
      @moduletag timeout: 30_000
      @moduletag capture_log: true
    end
  end
  
  @doc """
  Applies cache-related test tags.
  """
  defmacro cache_test_tags do
    quote do
      @moduletag :unit
      @moduletag area: :cache
      @moduletag performance: :fast
    end
  end
  
  @doc """
  Applies killmail processing test tags.
  """
  defmacro killmail_test_tags do
    quote do
      @moduletag :unit
      @moduletag area: :killmail_processing
      @moduletag performance: :medium
    end
  end
  
  @doc """
  Applies WebSocket test tags.
  """
  defmacro websocket_test_tags do
    quote do
      @moduletag :integration
      @moduletag area: :websocket
      @moduletag performance: :medium
      @moduletag timeout: 15_000
    end
  end
  
  @doc """
  Tags for tests that may be flaky due to timing or external dependencies.
  """
  defmacro flaky_test_tags do
    quote do
      @moduletag flaky: true
      @moduletag timeout: 30_000
      @moduletag capture_log: true
    end
  end
  
  @doc """
  Returns all available test type tags.
  """
  def test_types, do: [:unit, :integration, :external, :slow]
  
  @doc """
  Returns all available area tags.
  """
  def areas do
    [
      :cache,
      :api,
      :killmail_processing,
      :killmail_storage,
      :websocket,
      :esi,
      :zkb,
      :monitoring,
      :telemetry
    ]
  end
  
  @doc """
  Returns all available performance tags.
  """
  def performance_levels, do: [:fast, :medium, :slow]
end