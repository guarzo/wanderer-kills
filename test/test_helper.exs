# Start ExUnit first
ExUnit.start()

# Start Mox for test mocking
Application.ensure_all_started(:mox)

# Define mocks
Mox.defmock(WandererKills.Http.Client.Mock,
  for: WandererKills.Http.ClientBehaviour
)

Mox.defmock(WandererKills.Zkb.Client.Mock, for: WandererKills.Killmails.ZkbClientBehaviour)

# Mock for ESI client
Mox.defmock(EsiClientMock, for: WandererKills.ESI.ClientBehaviour)

# Start the application for testing
{:ok, _} = Application.ensure_all_started(:wanderer_kills)

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
# Mox.stub_with(WandererKills.Zkb.Client.Mock, WandererKills.Killmails.ZkbClient)

# Configure ExUnit to run tests sequentially
ExUnit.configure(parallel: false)

# Set the enricher for tests
ExUnit.configure(enricher: WandererKills.MockEnricher)

# Note: Cache clearing functionality is now available via WandererKills.TestHelpers.clear_all_caches()
