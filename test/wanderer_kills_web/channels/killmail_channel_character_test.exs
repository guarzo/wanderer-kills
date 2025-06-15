defmodule WandererKillsWeb.KillmailChannelCharacterTest do
  use WandererKillsWeb.ChannelCase, async: false
  use WandererKills.Test.SharedContexts

  setup :with_http_mocks

  # Helper function to broadcast killmail updates via PubSub
  defp broadcast_killmail_update(system_id, kills, opts \\ []) do
    message = %{
      type: :detailed_kill_update,
      solar_system_id: system_id,
      kills: kills,
      timestamp: DateTime.utc_now()
    }

    # Determine which topics to broadcast to
    topics =
      if Keyword.get(opts, :to_system, false) do
        # Broadcast to specific system topics
        ["zkb:system:#{system_id}", "zkb:system:#{system_id}:detailed"]
      else
        # Broadcast to all_systems topic for character-only subscriptions
        ["zkb:all_systems"]
      end

    Enum.each(topics, fn topic ->
      Phoenix.PubSub.broadcast(WandererKills.PubSub, topic, message)
    end)
  end

  setup do
    # Clear caches and indexes
    WandererKills.TestHelpers.clear_all_caches()
    
    # Try to clear indexes if they're available
    try do
      WandererKills.Subs.Subscriptions.CharacterIndex.clear()
      WandererKills.Subs.Subscriptions.SystemIndex.clear()
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end

    # Clear all subscriptions
    try do
      WandererKills.Subs.SubscriptionManager.clear_all_subscriptions()
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end

    # Create a socket with unique user_id for each test
    unique_user_id = "test_user_#{System.unique_integer([:positive])}"
    {:ok, socket} = connect(WandererKillsWeb.UserSocket, %{"user_id" => unique_user_id})

    %{socket: socket, user_id: unique_user_id}
  end

  describe "join with character_ids" do
    test "successfully joins with characters only", %{socket: socket} do
      {:ok, reply, _socket} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "characters" => [95_465_499, 90_379_338]
        })

      assert reply.status == "connected"
      assert reply.subscription_id
      assert reply.subscribed_systems == []
      assert reply.subscribed_characters == [95_465_499, 90_379_338]
    end

    test "successfully joins with both systems and characters", %{socket: socket} do
      {:ok, reply, _socket} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "systems" => [30_000_142, 30_000_143],
          "characters" => [95_465_499]
        })

      assert reply.status == "connected"
      assert reply.subscription_id
      assert reply.subscribed_systems == [30_000_142, 30_000_143]
      assert reply.subscribed_characters == [95_465_499]
    end

    test "validates character IDs are integers", %{socket: socket} do
      {:error, %{reason: reason}} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "characters" => ["not_an_integer", 123]
        })

      assert reason =~ "Character IDs must be integers"
    end

    test "validates character IDs are positive", %{socket: socket} do
      {:error, %{reason: reason}} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "characters" => [-1, 0, 123]
        })

      assert reason =~ "Invalid character IDs"
    end

    test "enforces maximum character limit", %{socket: socket} do
      # Create a list of 1001 character IDs (exceeds limit of 1000)
      too_many_characters = Enum.to_list(1..1001)

      {:error, %{reason: reason}} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "characters" => too_many_characters
        })

      assert reason =~ "Too many characters"
    end

    test "deduplicates character IDs", %{socket: socket} do
      {:ok, reply, _socket} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "characters" => [123, 456, 123, 789, 456]
        })

      assert reply.subscribed_characters == [123, 456, 789]
    end
  end

  describe "subscribe_characters" do
    setup %{socket: socket} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "systems" => [30_000_142],
          "characters" => [123]
        })

      %{channel_socket: socket}
    end

    test "adds new characters to subscription", %{channel_socket: socket} do
      ref = push(socket, "subscribe_characters", %{"characters" => [456, 789]})
      assert_reply(ref, :ok, %{subscribed_characters: characters})

      assert 123 in characters
      assert 456 in characters
      assert 789 in characters
      assert length(characters) == 3
    end

    test "ignores already subscribed characters", %{channel_socket: socket} do
      ref = push(socket, "subscribe_characters", %{"characters" => [123, 456]})
      assert_reply(ref, :ok, %{subscribed_characters: [123, 456]})

      # Try to subscribe to 123 again
      ref = push(socket, "subscribe_characters", %{"characters" => [123]})
      assert_reply(ref, :ok, %{message: "Already subscribed to all requested characters"})
    end

    test "validates character IDs", %{channel_socket: socket} do
      ref = push(socket, "subscribe_characters", %{"characters" => ["invalid"]})
      assert_reply(ref, :error, %{reason: reason})
      assert reason.message =~ "Character IDs must be integers"
    end
  end

  describe "unsubscribe_characters" do
    setup %{socket: socket} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "characters" => [123, 456, 789]
        })

      %{channel_socket: socket}
    end

    test "removes characters from subscription", %{channel_socket: socket} do
      ref = push(socket, "unsubscribe_characters", %{"characters" => [456]})
      assert_reply(ref, :ok, %{subscribed_characters: characters})

      assert characters == [123, 789]
    end

    test "handles unsubscribing from non-subscribed characters", %{channel_socket: socket} do
      ref = push(socket, "unsubscribe_characters", %{"characters" => [999]})
      assert_reply(ref, :ok, %{message: "Not subscribed to any of the requested characters"})
    end

    test "can unsubscribe from all characters", %{channel_socket: socket} do
      ref = push(socket, "unsubscribe_characters", %{"characters" => [123, 456, 789]})
      assert_reply(ref, :ok, %{subscribed_characters: []})
    end
  end

  describe "get_status with characters" do
    test "returns empty characters when none subscribed", %{socket: socket} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "systems" => [30_000_142]
        })

      ref = push(socket, "get_status", %{})
      assert_reply(ref, :ok, status)

      assert status.subscribed_systems == [30_000_142]
      assert status.subscribed_characters == []
    end

    test "returns subscribed characters", %{socket: socket} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "systems" => [30_000_142],
          "characters" => [123, 456]
        })

      ref = push(socket, "get_status", %{})
      assert_reply(ref, :ok, status)

      assert status.subscribed_systems == [30_000_142]
      assert status.subscribed_characters == [123, 456]
      assert status.subscription_id
      assert is_binary(status.user_id)
    end
  end

  describe "killmail filtering by character" do
    setup %{socket: socket} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "systems" => [],
          "characters" => [95_465_499, 90_379_338]
        })

      %{channel_socket: socket}
    end

    test "receives killmail when victim matches subscribed character", %{channel_socket: _socket} do
      killmail = %{
        "killmail_id" => 123_456,
        # Not subscribed to this system
        "solar_system_id" => 30_000_999,
        # Subscribed to this character
        "victim" => %{"character_id" => 95_465_499},
        "attackers" => [%{"character_id" => 999}]
      }

      # Simulate killmail broadcast
      broadcast_killmail_update(30_000_999, [killmail])

      assert_push("killmail_update", payload)
      assert payload.killmails == [killmail]
    end

    test "receives killmail when attacker matches subscribed character", %{
      channel_socket: _socket
    } do
      killmail = %{
        "killmail_id" => 123_457,
        "solar_system_id" => 30_000_999,
        "victim" => %{"character_id" => 999},
        "attackers" => [
          %{"character_id" => 111},
          # Subscribed to this character
          %{"character_id" => 90_379_338},
          %{"character_id" => 333}
        ]
      }

      broadcast_killmail_update(30_000_999, [killmail])

      assert_push("killmail_update", payload)
      assert payload.killmails == [killmail]
    end

    test "filters out killmails without matching characters", %{channel_socket: _socket} do
      killmail = %{
        "killmail_id" => 123_458,
        "solar_system_id" => 30_000_999,
        "victim" => %{"character_id" => 111},
        "attackers" => [%{"character_id" => 222}]
      }

      broadcast_killmail_update(30_000_999, [killmail])

      # Should not receive this killmail
      refute_push("killmail_update", _, 100)
    end

    test "filters multiple killmails correctly", %{channel_socket: _socket} do
      killmails = [
        %{
          "killmail_id" => 1,
          "solar_system_id" => 30_000_999,
          # Match
          "victim" => %{"character_id" => 95_465_499},
          "attackers" => []
        },
        %{
          "killmail_id" => 2,
          "solar_system_id" => 30_000_999,
          # No match
          "victim" => %{"character_id" => 111},
          "attackers" => []
        },
        %{
          "killmail_id" => 3,
          "solar_system_id" => 30_000_999,
          "victim" => %{"character_id" => 222},
          # Match
          "attackers" => [%{"character_id" => 90_379_338}]
        }
      ]

      broadcast_killmail_update(30_000_999, killmails)

      assert_push("killmail_update", payload)
      assert length(payload.killmails) == 2
      assert Enum.find(payload.killmails, &(&1["killmail_id"] == 1))
      assert Enum.find(payload.killmails, &(&1["killmail_id"] == 3))
      refute Enum.find(payload.killmails, &(&1["killmail_id"] == 2))
    end
  end

  describe "mixed system and character subscriptions" do
    setup %{socket: socket} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, "killmails:lobby", %{
          "systems" => [30_000_142],
          "characters" => [95_465_499]
        })

      %{channel_socket: socket}
    end

    test "receives killmail matching system but not character", %{channel_socket: _socket} do
      killmail = %{
        "killmail_id" => 123_459,
        # Subscribed system
        "solar_system_id" => 30_000_142,
        # Not subscribed character
        "victim" => %{"character_id" => 999},
        "attackers" => []
      }

      broadcast_killmail_update(30_000_142, [killmail], to_system: true)

      assert_push("killmail_update", payload)
      assert payload.killmails == [killmail]
    end

    test "receives killmail matching character but not system", %{channel_socket: _socket} do
      killmail = %{
        "killmail_id" => 123_460,
        # Not subscribed system
        "solar_system_id" => 30_000_999,
        # Subscribed character
        "victim" => %{"character_id" => 95_465_499},
        "attackers" => []
      }

      # Broadcast to the subscribed system's topic so channel receives it
      broadcast_killmail_update(30_000_142, [killmail], to_system: true)

      assert_push("killmail_update", payload)
      assert payload.killmails == [killmail]
    end

    test "receives killmail matching both system and character", %{channel_socket: _socket} do
      killmail = %{
        "killmail_id" => 123_461,
        # Subscribed system
        "solar_system_id" => 30_000_142,
        # Subscribed character
        "victim" => %{"character_id" => 95_465_499},
        "attackers" => []
      }

      broadcast_killmail_update(30_000_142, [killmail], to_system: true)

      assert_push("killmail_update", payload)
      assert payload.killmails == [killmail]
    end
  end
end
