# Start ExUnit first
ExUnit.start()

# Ensure Mox is available
Code.ensure_loaded?(Mox) || raise "Mox module not available. Run: mix deps.get && mix deps.compile"

# Define mocks
Mox.defmock(WandererKills.Ingest.Http.Client.Mock,
  for: WandererKills.Ingest.Http.ClientBehaviour
)

Mox.defmock(WandererKills.Ingest.Killmails.ZkbClient.Mock,
  for: WandererKills.Ingest.Killmails.ZkbClientBehaviour
)

# Mock for ESI client
Mox.defmock(EsiClientMock, for: WandererKills.Ingest.ESI.ClientBehaviour)

# Start the application for testing
{:ok, _} = Application.ensure_all_started(:wanderer_kills)

# Test support modules are auto-loaded by Mix

# Create a test case module that provides common setup for all tests
defmodule WandererKills.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      # Import common test utilities
      import WandererKills.TestHelpers
      import Mox

      # Setup mocks by default
      setup :verify_on_exit!

      # Make common aliases available
      alias WandererKills.Core.Cache
      alias WandererKills.TestHelpers
    end
  end

  setup do
    # Clear any existing processes and caches
    WandererKills.TestHelpers.clear_all_caches()
    :ok
  end
end

# Create a data case module for tests that need application supervision
defmodule WandererKills.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      # Import common test utilities
      import WandererKills.TestHelpers
      import WandererKills.Test.SharedContexts
      import Mox

      # Setup mocks by default
      setup :verify_on_exit!

      # Make common aliases available
      alias WandererKills.Core.Cache
      alias WandererKills.TestHelpers
    end
  end

  setup tags do
    # Clear caches on setup
    WandererKills.TestHelpers.clear_all_caches()

    # Setup mocks if not disabled
    unless tags[:no_mocks] do
      WandererKills.TestHelpers.setup_mocks()
    end

    :ok
  end
end

# Set up global mocks - do not stub with real implementation to allow proper mocking in tests
# Mox.stub_with(WandererKills.Ingest.Http.Client.Mock, WandererKills.Ingest.Http.Client)
# Mox.stub_with(WandererKills.Zkb.Client.Mock, WandererKills.Ingest.Killmails.ZkbClient)

# Configure ExUnit to run tests sequentially
ExUnit.configure(parallel: false)

# Set the enricher for tests
ExUnit.configure(enricher: WandererKills.MockEnricher)

# Note: Cache clearing functionality is now available via WandererKills.TestHelpers.clear_all_caches()
