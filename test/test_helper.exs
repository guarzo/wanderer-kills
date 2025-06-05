# Start test-specific cache instances
:ets.new(:killmails_cache_test, [:named_table, :public, :set])
:ets.new(:system_cache_test, [:named_table, :public, :set])
:ets.new(:esi_cache_test, [:named_table, :public, :set])

# Define the ZkbClient behaviour
defmodule WandererKills.Data.Sources.ZkbClientBehaviour do
  @moduledoc """
  Behaviour for zKillboard API client.
  """

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type killmail :: map()

  @callback fetch_killmail(killmail_id()) :: {:ok, killmail()} | {:error, term()}
  @callback fetch_system_killmails(system_id()) :: {:ok, [killmail()]} | {:error, term()}
  @callback fetch_system_killmails_esi(system_id()) :: {:ok, [killmail()]} | {:error, term()}
  @callback enrich_killmail(killmail()) :: {:ok, killmail()} | {:error, term()}
  @callback get_system_kill_count(system_id()) :: {:ok, non_neg_integer()} | {:error, term()}
end

# Define mocks
Mox.defmock(WandererKills.Http.Client.Mock, for: WandererKills.Http.ClientBehaviour)
Mox.defmock(WandererKills.Zkb.Client.Mock, for: WandererKills.Data.Sources.ZkbClientBehaviour)

Mox.defmock(WandererKills.Data.Sources.ZkbClient.Mock,
  for: WandererKills.Data.Sources.ZkbClientBehaviour
)

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

# Set up global mocks
Mox.stub_with(WandererKills.Http.Client.Mock, WandererKills.Http.Client)
Mox.stub_with(WandererKills.Zkb.Client.Mock, WandererKills.Data.Sources.ZkbClient)
Mox.stub_with(WandererKills.Data.Sources.ZkbClient.Mock, WandererKills.Data.Sources.ZkbClient)

# Configure ExUnit to run tests sequentially
ExUnit.configure(parallel: false)

# Set the enricher for tests
ExUnit.configure(enricher: WandererKills.MockEnricher)

# Note: Cache clearing functionality is now available via WandererKills.TestHelpers.clear_all_caches()
