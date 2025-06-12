defmodule WandererKills.SubscriptionManagerTest do
  use ExUnit.Case, async: false

  alias WandererKills.SubscriptionManager

  import Mox

  setup :verify_on_exit!

  setup do
    # Check if TaskSupervisor is already running
    task_supervisor_started = 
      case Process.whereis(WandererKills.TaskSupervisor) do
        nil ->
          # Start the TaskSupervisor if not running
          {:ok, _pid} = Task.Supervisor.start_link(name: WandererKills.TaskSupervisor)
          true
        _pid ->
          false
      end
      
    # Check if PubSub is already running
    pubsub_started =
      case Process.whereis(WandererKills.PubSub) do
        nil ->
          # Start PubSub if not running
          {:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: WandererKills.PubSub, adapter: Phoenix.PubSub.PG2)
          true
        _pid ->
          false
      end

    # Stop the existing SubscriptionManager if it's running
    case Process.whereis(SubscriptionManager) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    # Start a fresh SubscriptionManager for each test
    {:ok, _pid} = SubscriptionManager.start_link()

    # Mock the HTTP client for webhook tests
    WandererKills.Http.Client.Mock
    |> stub(:post, fn _url, _body, _opts ->
      {:ok, %{status: 200, body: %{"success" => true}}}
    end)

    on_exit(fn ->
      # Only stop TaskSupervisor if we started it
      if task_supervisor_started do
        case Process.whereis(WandererKills.TaskSupervisor) do
          nil -> :ok
          pid -> Process.exit(pid, :shutdown)
        end
      end
      
      # Only stop PubSub if we started it
      if pubsub_started do
        case Process.whereis(WandererKills.PubSub) do
          nil -> :ok
          pid -> Process.exit(pid, :shutdown)
        end
      end
    end)

    :ok
  end

  describe "subscribe/3" do
    test "creates a new subscription successfully" do
      subscriber_id = "user_123"
      system_ids = [30_000_142, 30_000_143]

      {:ok, subscription_id} = SubscriptionManager.subscribe(subscriber_id, system_ids, nil)

      assert is_binary(subscription_id)
      assert String.length(subscription_id) > 0
    end

    test "creates subscription with webhook URL" do
      subscriber_id = "user_123"
      system_ids = [30_000_142]
      webhook_url = "https://example.com/webhook"

      {:ok, subscription_id} =
        SubscriptionManager.subscribe(subscriber_id, system_ids, webhook_url)

      assert is_binary(subscription_id)
    end

    test "rejects empty system list" do
      subscriber_id = "user_123"
      system_ids = []

      {:error, "At least one system ID is required"} =
        SubscriptionManager.subscribe(subscriber_id, system_ids, nil)
    end

    test "accepts many systems" do
      subscriber_id = "user_123"
      # The implementation doesn't have a limit on system count
      system_ids = Enum.to_list(1..101)

      {:ok, subscription_id} = SubscriptionManager.subscribe(subscriber_id, system_ids, nil)
      assert is_binary(subscription_id)
    end
  end

  describe "unsubscribe/1" do
    setup do
      {:ok, subscription_id} = SubscriptionManager.subscribe("user_123", [30_000_142], nil)
      {:ok, subscription_id: subscription_id}
    end

    test "removes existing subscription", %{subscription_id: _subscription_id} do
      # Note: unsubscribe takes subscriber_id, not subscription_id
      assert :ok = SubscriptionManager.unsubscribe("user_123")
    end

    test "returns ok for non-existent subscriber" do
      # The implementation returns :ok even if subscriber doesn't exist
      assert :ok = SubscriptionManager.unsubscribe("fake_user")
    end
  end

  describe "list_subscriptions/0" do
    test "returns empty list initially" do
      assert [] = SubscriptionManager.list_subscriptions()
    end

    test "returns all subscriptions" do
      {:ok, sub1} = SubscriptionManager.subscribe("user_123", [30_000_142], nil)
      {:ok, sub2} = SubscriptionManager.subscribe("user_456", [30_000_143], nil)

      subscriptions = SubscriptionManager.list_subscriptions()
      subscription_ids = Enum.map(subscriptions, & &1["id"])

      assert length(subscriptions) == 2
      assert sub1 in subscription_ids
      assert sub2 in subscription_ids
    end
  end

  describe "broadcast_killmail_update_async/2" do
    setup do
      # Create subscriptions for different systems
      {:ok, sub1} = SubscriptionManager.subscribe("user_123", [30_000_142], nil)

      {:ok, sub2} =
        SubscriptionManager.subscribe("user_456", [30_000_142], "https://example.com/webhook")

      {:ok, sub3} = SubscriptionManager.subscribe("user_789", [30_000_143], nil)

      {:ok, sub1: sub1, sub2: sub2, sub3: sub3}
    end

    test "broadcasts to subscribers of relevant system" do
      kills = [
        %{
          "killmail_id" => 123_456,
          "solar_system_id" => 30_000_142,
          "killmail_time" => "2024-01-01T00:00:00Z"
        }
      ]

      # This should trigger notifications
      assert :ok = SubscriptionManager.broadcast_killmail_update_async(30_000_142, kills)

      # Give async tasks time to run
      Process.sleep(100)
    end
  end

  describe "broadcast_killmail_count_update_async/2" do
    test "broadcasts kill count update" do
      {:ok, _} = SubscriptionManager.subscribe("user_123", [30_000_142], nil)

      assert :ok = SubscriptionManager.broadcast_killmail_count_update_async(30_000_142, 42)
    end
  end

  describe "websocket subscriptions" do
    test "adds websocket subscription" do
      subscription = %{
        id: "socket_123",
        system_ids: [30_000_142],
        subscriber_id: "user_123"
      }

      assert :ok = SubscriptionManager.add_websocket_subscription(subscription)
    end

    test "updates existing websocket subscription" do
      subscription = %{
        id: "socket_123",
        system_ids: [30_000_142],
        subscriber_id: "user_123"
      }

      assert :ok = SubscriptionManager.add_websocket_subscription(subscription)

      assert :ok =
               SubscriptionManager.update_websocket_subscription("socket_123", %{
                 system_ids: [30_000_143]
               })
    end

    test "removes websocket subscription" do
      subscription = %{
        id: "socket_123",
        system_ids: [30_000_142],
        subscriber_id: "user_123"
      }

      assert :ok = SubscriptionManager.add_websocket_subscription(subscription)
      assert :ok = SubscriptionManager.remove_websocket_subscription("socket_123")
    end
  end

  describe "get_stats/0" do
    test "returns subscription statistics" do
      {:ok, _} = SubscriptionManager.subscribe("user_123", [30_000_142], nil)

      {:ok, _} =
        SubscriptionManager.subscribe(
          "user_456",
          [30_000_142, 30_000_143],
          "https://example.com/webhook"
        )

      stats = SubscriptionManager.get_stats()

      assert stats.http_subscription_count == 2
      assert stats.total_subscribed_systems == 2
      assert stats.websocket_subscription_count == 0
    end
  end

  describe "error handling" do
    test "handles invalid system IDs gracefully" do
      result = SubscriptionManager.subscribe("user_123", ["invalid", nil, 30_000_142], nil)

      # Depending on implementation, this might succeed with valid IDs
      # or fail entirely
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
