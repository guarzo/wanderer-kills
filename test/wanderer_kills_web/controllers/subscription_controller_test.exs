defmodule WandererKillsWeb.SubscriptionControllerTest do
  use WandererKillsWeb.ConnCase
  use WandererKills.Test.SharedContexts

  alias WandererKills.SubscriptionManager

  setup do
    # Clear state without restarting the application
    WandererKills.TestHelpers.clear_all_caches()
    WandererKills.Subscriptions.CharacterIndex.clear()
    WandererKills.Subscriptions.SystemIndex.clear()
    
    # Clear any existing webhook subscriptions
    WandererKills.SubscriptionManager.clear_all_webhook_subscriptions()

    :ok
  end

  describe "POST /api/v1/subscriptions" do
    test "creates subscription with system_ids only", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        "system_ids" => [30_000_142, 30_000_143],
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "data" => %{
                 "subscription_id" => subscription_id,
                 "message" => "Subscription created successfully"
               }
             } = json_response(conn, 201)

      assert is_binary(subscription_id)
      assert String.starts_with?(subscription_id, "sub_")
    end

    test "creates subscription with character_ids only", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        "character_ids" => [95_465_499, 90_379_338],
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "data" => %{
                 "subscription_id" => _subscription_id,
                 "message" => "Subscription created successfully"
               }
             } = json_response(conn, 201)
    end

    test "creates subscription with both system_ids and character_ids", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        "system_ids" => [30_000_142],
        "character_ids" => [95_465_499],
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "data" => %{
                 "subscription_id" => _subscription_id,
                 "message" => "Subscription created successfully"
               }
             } = json_response(conn, 201)

      # Verify the subscription was created with both filters
      subscriptions = SubscriptionManager.list_subscriptions()
      assert length(subscriptions) == 1

      [subscription] = subscriptions
      assert subscription["system_ids"] == [30_000_142]
      assert subscription["character_ids"] == [95_465_499]
    end

    test "validates subscriber_id is required", %{conn: conn} do
      params = %{
        "system_ids" => [30_000_142],
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "error" => %{
                 "message" => "subscriber_id is required"
               }
             } = json_response(conn, 400)
    end

    test "validates callback_url is required", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        "system_ids" => [30_000_142]
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "error" => %{
                 "message" => "callback_url is required"
               }
             } = json_response(conn, 400)
    end

    test "validates callback_url must be valid HTTP/HTTPS URL", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        "system_ids" => [30_000_142],
        "callback_url" => "not-a-url"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "error" => %{
                 "message" => "callback_url must be a valid HTTP/HTTPS URL"
               }
             } = json_response(conn, 400)
    end

    test "validates at least one filter is required", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "error" => %{
                 "message" => "At least one system_id or character_id is required"
               }
             } = json_response(conn, 400)
    end

    test "validates system_ids must be positive integers", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        "system_ids" => [-1, 0, "not_a_number"],
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "error" => %{
                 "message" => "system_ids must be an array of positive integers"
               }
             } = json_response(conn, 400)
    end

    test "validates character_ids must be positive integers", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        "character_ids" => [-1, 0, "not_a_number"],
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "error" => %{
                 "message" => "character_ids must be an array of positive integers"
               }
             } = json_response(conn, 400)
    end

    test "enforces maximum system_ids limit", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        # 101 systems
        "system_ids" => Enum.to_list(1..101),
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "error" => %{
                 "message" => "Maximum 100 system_ids allowed per subscription"
               }
             } = json_response(conn, 400)
    end

    test "enforces maximum character_ids limit", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        # 1001 characters
        "character_ids" => Enum.to_list(1..1001),
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert %{
               "error" => %{
                 "message" => "Maximum 1000 character_ids allowed per subscription"
               }
             } = json_response(conn, 400)
    end

    test "deduplicates and sorts IDs", %{conn: conn} do
      params = %{
        "subscriber_id" => "test_user_123",
        "system_ids" => [30_000_143, 30_000_142, 30_000_143],
        "character_ids" => [789, 123, 456, 123],
        "callback_url" => "https://example.com/webhook"
      }

      conn = post(conn, "/api/v1/subscriptions", params)

      assert json_response(conn, 201)

      # Verify the subscription has deduplicated and sorted IDs
      subscriptions = SubscriptionManager.list_subscriptions()
      [subscription] = subscriptions

      assert subscription["system_ids"] == [30_000_142, 30_000_143]
      assert subscription["character_ids"] == [123, 456, 789]
    end
  end

  describe "GET /api/v1/subscriptions" do
    setup do
      # Create some test subscriptions
      {:ok, sub1} =
        SubscriptionManager.add_subscription(%{
          "subscriber_id" => "user1",
          "system_ids" => [30_000_142],
          "character_ids" => [],
          "callback_url" => "https://example.com/webhook1"
        })

      {:ok, sub2} =
        SubscriptionManager.add_subscription(%{
          "subscriber_id" => "user2",
          "system_ids" => [],
          "character_ids" => [95_465_499],
          "callback_url" => "https://example.com/webhook2"
        })

      %{subscription_ids: [sub1, sub2]}
    end

    test "lists all subscriptions", %{conn: conn, subscription_ids: _} do
      conn = get(conn, "/api/v1/subscriptions")

      assert %{
               "data" => %{
                 "subscriptions" => subscriptions,
                 "count" => 2
               }
             } = json_response(conn, 200)

      assert length(subscriptions) == 2

      # Check first subscription
      sub1 = Enum.find(subscriptions, &(&1["subscriber_id"] == "user1"))
      assert sub1["system_ids"] == [30_000_142]
      assert sub1["character_ids"] == []

      # Check second subscription
      sub2 = Enum.find(subscriptions, &(&1["subscriber_id"] == "user2"))
      assert sub2["system_ids"] == []
      assert sub2["character_ids"] == [95_465_499]
    end
  end

  describe "GET /api/v1/subscriptions/stats" do
    setup do
      # Create test subscriptions
      SubscriptionManager.add_subscription(%{
        "subscriber_id" => "user1",
        "system_ids" => [30_000_142, 30_000_143],
        "character_ids" => [123],
        "callback_url" => "https://example.com/webhook1"
      })

      SubscriptionManager.add_subscription(%{
        "subscriber_id" => "user2",
        # Duplicate system
        "system_ids" => [30_000_142],
        "character_ids" => [456, 789],
        "callback_url" => "https://example.com/webhook2"
      })

      :ok
    end

    test "returns subscription statistics", %{conn: conn} do
      conn = get(conn, "/api/v1/subscriptions/stats")

      assert %{
               "data" => %{
                 "http_subscription_count" => 2,
                 "websocket_subscription_count" => 0,
                 # 30000142 and 30000143 (deduplicated)
                 "total_subscribed_systems" => 2,
                 # 123, 456, 789
                 "total_subscribed_characters" => 3
               }
             } = json_response(conn, 200)
    end
  end

  describe "DELETE /api/v1/subscriptions/:subscriber_id" do
    setup do
      # Create test subscriptions
      SubscriptionManager.add_subscription(%{
        "subscriber_id" => "user_to_delete",
        "system_ids" => [30_000_142],
        "character_ids" => [],
        "callback_url" => "https://example.com/webhook"
      })

      SubscriptionManager.add_subscription(%{
        "subscriber_id" => "other_user",
        "system_ids" => [30_000_143],
        "character_ids" => [],
        "callback_url" => "https://example.com/webhook2"
      })

      :ok
    end

    test "unsubscribes a specific subscriber", %{conn: conn} do
      # Verify subscriptions exist before delete
      subscriptions = SubscriptionManager.list_subscriptions()
      assert length(subscriptions) == 2

      conn = delete(conn, "/api/v1/subscriptions/user_to_delete")

      assert %{
               "data" => %{
                 "message" => "Successfully unsubscribed",
                 "subscriber_id" => "user_to_delete"
               }
             } = json_response(conn, 200)

      # Verify only the correct subscription was deleted
      subscriptions = SubscriptionManager.list_subscriptions()
      assert length(subscriptions) == 1
      assert hd(subscriptions)["subscriber_id"] == "other_user"
    end

    test "handles non-existent subscriber gracefully", %{conn: conn} do
      conn = delete(conn, "/api/v1/subscriptions/non_existent_user")

      assert %{
               "data" => %{
                 "message" => "Successfully unsubscribed",
                 "subscriber_id" => "non_existent_user"
               }
             } = json_response(conn, 200)
    end
  end
end
