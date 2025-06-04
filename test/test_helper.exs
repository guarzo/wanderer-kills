ExUnit.start()

# Configure cache names for test environment to use the same names as the application
# but with test-specific instances
Application.put_env(:wanderer_kills, :killmails_cache_name, :wanderer_test_killmails_cache)
Application.put_env(:wanderer_kills, :system_cache_name, :wanderer_test_system_cache)
Application.put_env(:wanderer_kills, :esi_cache_name, :wanderer_test_esi_cache)

# Start test-specific cache instances
{:ok, _} = Cachex.start_link(:wanderer_test_killmails_cache)
{:ok, _} = Cachex.start_link(:wanderer_test_system_cache)
{:ok, _} = Cachex.start_link(:wanderer_test_esi_cache)

# Start the application for testing - this will start its own production caches
Application.ensure_all_started(:wanderer_kills)

# Define the mock zkb client behavior
defmodule WandererKills.Zkb.ClientBehaviour do
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

# Set global mode for all mocks - this makes mocks available to all processes
Mox.defmock(WandererKills.Http.Client.Mock, for: WandererKills.Http.ClientBehaviour)
Mox.defmock(WandererKills.Zkb.Client.Mock, for: WandererKills.Zkb.ClientBehaviour)

Application.put_env(:mox, :global_for, [
  WandererKills.Http.Client.Mock,
  WandererKills.Zkb.Client.Mock
])

# Set up mocks for all tests
WandererKills.TestHelpers.setup_mocks()

# Mock enrichment module for tests
defmodule WandererKills.MockEnricher do
  def enrich_killmail(killmail), do: {:ok, killmail}
end

Application.put_env(:wanderer_kills, :enricher, WandererKills.MockEnricher)
Application.put_env(:wanderer_kills, :http_client, WandererKills.MockHttpClient)
Application.put_env(:wanderer_kills, :zkb_client, WandererKills.Zkb.Client.Mock)

# Note: Cache clearing functionality is now available via WandererKills.TestHelpers.clear_all_caches()
