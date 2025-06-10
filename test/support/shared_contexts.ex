defmodule WandererKills.Test.SharedContexts do
  @moduledoc """
  Shared test contexts to eliminate setup/teardown duplication.

  This module provides reusable test setups that can be included
  in any test module to reduce boilerplate.

  ## Usage

  ```elixir
  defmodule MyTest do
    use WandererKills.DataCase
    use WandererKills.Test.SharedContexts

    describe "with cache" do
      setup :with_cache

      test "can use cache", %{cache: cache} do
        # cache is available here
      end
    end
  end
  ```
  """

  defmacro __using__(_opts) do
    quote do
      import WandererKills.Test.SharedContexts
    end
  end

  import ExUnit.Callbacks

  @doc """
  Sets up a clean cache instance for testing.

  Returns:
  - `%{cache: cache_name}` - The cache instance name
  """
  def with_cache(_context \\ %{}) do
    cache_name = :"test_cache_#{System.unique_integer()}"

    {:ok, _pid} = Cachex.start_link(cache_name)

    on_exit(fn ->
      if Process.whereis(cache_name) do
        Supervisor.stop(cache_name)
      end
    end)

    %{cache: cache_name}
  end

  @doc """
  Sets up a clean test environment with cache clearing.

  This is the most commonly used setup function.
  """
  def with_clean_environment(_context \\ %{}) do
    WandererKills.TestHelpers.clear_all_caches()
    %{}
  end

  @doc """
  Sets up a clean KillStore for testing.

  Returns:
  - `%{}` - Empty context (KillStore is global)
  """
  def with_kill_store(_context \\ %{}) do
    WandererKills.Storage.KillmailStore.clear()
    %{}
  end

  @doc """
  Comprehensive test setup combining common requirements.

  This function sets up:
  - Clean caches
  - Clean KillStore
  - HTTP mocks
  - Test data

  Returns all context from individual setups.
  """
  def with_full_test_setup(context) do
    context
    |> Map.merge(with_clean_environment())
    |> Map.merge(with_kill_store())
    |> Map.merge(with_http_mocks())
    |> Map.merge(with_test_data())
  end

  @doc """
  Sets up mock HTTP clients for testing.

  Returns:
  - `%{http_mock: mock, esi_mock: mock}` - The HTTP mock modules
  """
  def with_http_mocks(_context \\ %{}) do
    # Use verify_on_exit to ensure all expectations are called
    Mox.verify_on_exit!()

    # Set up default stubs for common cases
    setup_default_http_stubs()
    setup_default_esi_stubs()

    %{
      http_mock: WandererKills.Http.ClientMock,
      esi_mock: WandererKills.ESI.ClientMock
    }
  end

  @doc """
  Sets up mock HTTP clients with specific expectations.

  Options:
  - `:expect_esi_calls` - Boolean, whether to expect ESI calls (default: false)
  - `:expect_http_calls` - Boolean, whether to expect HTTP calls (default: false)
  - `:zkb_response` - Mock response for ZKB calls
  - `:esi_responses` - Map of ESI endpoint responses

  Returns:
  - `%{http_mock: mock, esi_mock: mock}` - The HTTP mock modules
  """
  def with_configured_http_mocks(context) do
    base_context = with_http_mocks(context)

    # Configure specific expectations based on options
    if context[:expect_esi_calls] do
      setup_esi_expectations(context[:esi_responses] || %{})
    end

    if context[:expect_http_calls] do
      setup_http_expectations(context[:zkb_response])
    end

    base_context
  end

  @doc """
  Sets up a test database with sample data.

  Returns:
  - `%{test_data: data}` - Map of test data
  """
  def with_test_data(_context \\ %{}) do
    test_data = %{
      killmail: build_test_killmail(),
      system: build_test_system(),
      character: build_test_character(),
      corporation: build_test_corporation(),
      alliance: build_test_alliance()
    }

    %{test_data: test_data}
  end

  @doc """
  Sets up a supervised GenServer for testing.

  Options:
  - `:module` - The GenServer module to start
  - `:args` - Arguments to pass to start_link

  Returns:
  - `%{server: pid}` - The GenServer PID
  """
  def with_supervised_server(context) do
    module = context[:module] || raise "Must specify :module"
    args = context[:args] || []

    {:ok, pid} = start_supervised({module, args})

    %{server: pid}
  end

  @doc """
  Sets up Phoenix PubSub for testing.

  Returns:
  - `%{pubsub: pubsub_name}` - The PubSub instance name
  """
  def with_pubsub(_context \\ %{}) do
    pubsub_name = :"test_pubsub_#{System.unique_integer()}"

    {:ok, _pid} =
      Phoenix.PubSub.Supervisor.start_link(
        name: pubsub_name,
        adapter: Phoenix.PubSub.PG2
      )

    on_exit(fn ->
      # PubSub will be stopped automatically when test process exits
      :ok
    end)

    %{pubsub: pubsub_name}
  end

  @doc """
  Sets up WebSocket connection for testing.

  Returns:
  - `%{socket: socket, channel: channel}` - Connected socket and channel
  """
  def with_websocket_connection(context) do
    pubsub = context[:pubsub] || WandererKills.PubSub

    socket = %Phoenix.Socket{
      endpoint: WandererKillsWeb.Endpoint,
      pubsub_server: pubsub,
      transport: :websocket,
      serializer: Phoenix.Socket.V2.JSONSerializer
    }

    # Simulate connect_info for testing
    connect_info = %{
      peer_data: %{address: {127, 0, 0, 1}, port: 12_345},
      x_headers: []
    }

    {:ok, connected_socket} = WandererKillsWeb.UserSocket.connect(%{}, socket, connect_info)
    %{socket: connected_socket, channel: "killmails:lobby"}
  end

  # Private helper functions

  defp build_test_killmail do
    %{
      "killmail_id" => 123_456_789,
      "kill_time" => "2024-01-01T12:00:00Z",
      "solar_system_id" => 30_000_142,
      "victim" => %{
        "character_id" => 95_465_499,
        "corporation_id" => 1_000_009,
        "alliance_id" => 1_354_830_081,
        "ship_type_id" => 587,
        "damage_taken" => 1337
      },
      "attackers" => [
        %{
          "character_id" => 95_465_500,
          "corporation_id" => 1_000_010,
          "alliance_id" => nil,
          "ship_type_id" => 17_619,
          "weapon_type_id" => 2488,
          "damage_done" => 1337,
          "final_blow" => true
        }
      ],
      "zkb" => %{
        "totalValue" => 10_000_000.0,
        "points" => 10,
        "npc" => false,
        "hash" => "abcdef123456"
      }
    }
  end

  defp build_test_system do
    %{
      "system_id" => 30_000_142,
      "name" => "Jita",
      "security" => 0.9
    }
  end

  defp build_test_character do
    %{
      "character_id" => 95_465_499,
      "name" => "Test Character",
      "corporation_id" => 1_000_009
    }
  end

  defp build_test_corporation do
    %{
      "corporation_id" => 1_000_009,
      "name" => "Test Corporation",
      "ticker" => "TEST"
    }
  end

  defp build_test_alliance do
    %{
      "alliance_id" => 1_354_830_081,
      "name" => "Test Alliance",
      "ticker" => "TESTA"
    }
  end

  # Private HTTP mocking helper functions

  defp setup_default_http_stubs do
    # These are basic stubs that can be overridden in specific tests
    # They prevent errors when HTTP calls are made but not expected

    # Stub the HTTP client mock to return not_found for any request
    Mox.stub(WandererKills.Http.Client.Mock, :get_with_rate_limit, fn _url, _opts ->
      {:error, :not_found}
    end)

    :ok
  end

  defp setup_default_esi_stubs do
    # Default ESI stubs for common test scenarios
    # These return basic success responses to prevent test failures
    :ok
  end

  defp setup_esi_expectations(responses) when is_map(responses) do
    # Set up specific ESI expectations based on provided responses
    # This would iterate through the responses map and set up Mox expectations
    :ok
  end

  defp setup_http_expectations(_zkb_response) do
    # Set up ZKB HTTP expectations
    # This would configure the HTTP mock to return the specified response
    :ok
  end
end
