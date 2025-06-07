# Start test-specific cache instances
:ets.new(:killmails_cache_test, [:named_table, :public, :set])
:ets.new(:system_cache_test, [:named_table, :public, :set])
:ets.new(:esi_cache_test, [:named_table, :public, :set])

# Define mocks
Mox.defmock(WandererKills.Http.Client.Mock,
  for: WandererKills.Infrastructure.Behaviours.HttpClient
)

Mox.defmock(WandererKills.Zkb.Client.Mock, for: WandererKills.Zkb.ClientBehaviour)

# Start ExUnit
ExUnit.start()

# Start the application for testing
Application.ensure_all_started(:wanderer_kills)

# Create a test case module that provides common setup for all tests
defmodule WandererKills.TestCase do
  use ExUnit.CaseTemplate

  setup do
    # Clear any existing processes and caches
    WandererKills.TestHelpers.clear_all_caches()
    :ok
  end
end

# Set up global mocks - do not stub with real implementation to allow proper mocking in tests
# Mox.stub_with(WandererKills.Http.Client.Mock, WandererKills.Http.Client)
# Mox.stub_with(WandererKills.Zkb.Client.Mock, WandererKills.Zkb.Client)

# Configure ExUnit to run tests sequentially
ExUnit.configure(parallel: false)

# Set the enricher for tests
ExUnit.configure(enricher: WandererKills.MockEnricher)

# Note: Cache clearing functionality is now available via WandererKills.TestHelpers.clear_all_caches()
