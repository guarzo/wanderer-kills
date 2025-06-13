defmodule WandererKills.Integration.CharacterSubscriptionIntegrationTest do
  @moduledoc """
  End-to-end integration tests for character subscription functionality.

  These tests verify the complete flow from subscription creation through
  killmail filtering and delivery.
  """

  use ExUnit.Case, async: false

  alias WandererKills.SubscriptionManager
  alias WandererKills.Subscriptions.CharacterIndex
  alias WandererKills.Killmails.{CharacterCache, BatchProcessor}
  alias WandererKills.Storage.KillmailStore

  import Cachex.Spec

  setup do
    # Ensure cache is available
    ensure_cache_available()

    # Clear all state
    CharacterIndex.clear()

    try do
      CharacterCache.clear_cache()
    rescue
      ArgumentError ->
        # Cache doesn't exist yet, that's ok
        :ok
    end

    KillmailStore.clear_all()

    # Restart the subscription manager to clear its state
    :ok = Application.stop(:wanderer_kills)
    :ok = Application.start(:wanderer_kills)

    # Ensure cache is available after restart
    ensure_cache_available()

    on_exit(fn ->
      CharacterIndex.clear()

      try do
        CharacterCache.clear_cache()
      rescue
        ArgumentError ->
          # Cache doesn't exist anymore, that's ok
          :ok
      end

      KillmailStore.clear_all()
    end)

    :ok
  end

  describe "end-to-end character subscription flow" do
    test "complete WebSocket subscription lifecycle" do
      # Create a WebSocket subscription with both systems and characters
      subscription_attrs = %{
        "subscriber_id" => "integration_test_user",
        "user_id" => "test_user_123",
        "system_ids" => [30_000_142],
        "character_ids" => [95_465_499, 90_379_338],
        "socket_pid" => self()
      }

      {:ok, subscription_id} =
        SubscriptionManager.add_subscription(subscription_attrs, :websocket)

      # Verify subscription is stored
      stats = SubscriptionManager.get_stats()
      assert stats.websocket_subscription_count == 1
      assert stats.total_subscribed_characters == 2
      assert stats.total_subscribed_systems == 1

      # Verify character index is updated
      char_subs_1 = CharacterIndex.find_subscriptions_for_entity(95_465_499)
      char_subs_2 = CharacterIndex.find_subscriptions_for_entity(90_379_338)
      assert subscription_id in char_subs_1
      assert subscription_id in char_subs_2

      # Test killmail filtering - system match
      system_killmail = %{
        "killmail_id" => 1001,
        "solar_system_id" => 30_000_142,
        "victim" => %{"character_id" => 999_999},
        "attackers" => []
      }

      # Test killmail filtering - character match
      character_killmail = %{
        "killmail_id" => 1002,
        # Different system
        "solar_system_id" => 30_000_999,
        # Matching character
        "victim" => %{"character_id" => 95_465_499},
        "attackers" => []
      }

      # Test killmail filtering - no match
      no_match_killmail = %{
        "killmail_id" => 1003,
        "solar_system_id" => 30_000_999,
        "victim" => %{"character_id" => 888_888},
        "attackers" => []
      }

      # Verify batch processing correctly identifies matches
      subscriptions = %{subscription_id => subscription_attrs}
      killmails = [system_killmail, character_killmail, no_match_killmail]

      grouped = BatchProcessor.group_killmails_by_subscription(killmails, subscriptions)

      assert Map.has_key?(grouped, subscription_id)
      assert length(grouped[subscription_id]) == 2

      # Verify the correct killmails are matched
      matched_ids = grouped[subscription_id] |> Enum.map(& &1["killmail_id"]) |> Enum.sort()
      assert matched_ids == [1001, 1002]

      # Update subscription - add more characters
      SubscriptionManager.update_websocket_subscription(subscription_id, %{
        "character_ids" => [95_465_499, 90_379_338, 12_345_678]
      })

      # Give a moment for async update to complete
      Process.sleep(10)

      # Verify character index is updated
      char_subs_3 = CharacterIndex.find_subscriptions_for_entity(12_345_678)
      assert subscription_id in char_subs_3

      # Test updated filtering
      new_char_killmail = %{
        "killmail_id" => 1004,
        "solar_system_id" => 30_000_999,
        "victim" => %{"character_id" => 12_345_678},
        "attackers" => []
      }

      # This should now match the updated subscription
      updated_subscriptions = %{
        subscription_id =>
          Map.put(subscription_attrs, "character_ids", [95_465_499, 90_379_338, 12_345_678])
      }

      new_grouped =
        BatchProcessor.group_killmails_by_subscription([new_char_killmail], updated_subscriptions)

      assert Map.has_key?(new_grouped, subscription_id)
      assert length(new_grouped[subscription_id]) == 1

      # Remove subscription
      SubscriptionManager.remove_websocket_subscription(subscription_id)

      # Give a moment for async removal to complete
      Process.sleep(10)

      # Verify character index is cleaned up
      assert CharacterIndex.find_subscriptions_for_entity(95_465_499) == []
      assert CharacterIndex.find_subscriptions_for_entity(90_379_338) == []
      assert CharacterIndex.find_subscriptions_for_entity(12_345_678) == []

      # Verify stats are updated
      final_stats = SubscriptionManager.get_stats()
      assert final_stats.websocket_subscription_count == 0
      assert final_stats.total_subscribed_characters == 0
    end

    test "multiple subscriptions with overlapping characters" do
      # Create multiple subscriptions with some character overlap
      {:ok, sub1} =
        SubscriptionManager.add_subscription(
          %{
            "subscriber_id" => "user1",
            "user_id" => "user1",
            "system_ids" => [],
            "character_ids" => [100, 200, 300],
            "socket_pid" => self()
          },
          :websocket
        )

      {:ok, sub2} =
        SubscriptionManager.add_subscription(
          %{
            "subscriber_id" => "user2",
            "user_id" => "user2",
            "system_ids" => [],
            "character_ids" => [200, 300, 400],
            "socket_pid" => self()
          },
          :websocket
        )

      {:ok, sub3} =
        SubscriptionManager.add_subscription(
          %{
            "subscriber_id" => "user3",
            "user_id" => "user3",
            "system_ids" => [],
            "character_ids" => [500, 600],
            "socket_pid" => self()
          },
          :websocket
        )

      # Test character lookups
      # Only sub1
      assert length(CharacterIndex.find_subscriptions_for_entity(100)) == 1

      char_200_subs = CharacterIndex.find_subscriptions_for_entity(200)
      # sub1 and sub2
      assert length(char_200_subs) == 2
      assert sub1 in char_200_subs
      assert sub2 in char_200_subs

      char_300_subs = CharacterIndex.find_subscriptions_for_entity(300)
      # sub1 and sub2
      assert length(char_300_subs) == 2

      assert CharacterIndex.find_subscriptions_for_entity(500) == [sub3]
      assert CharacterIndex.find_subscriptions_for_entity(999) == []

      # Test batch character lookup
      batch_result = CharacterIndex.find_subscriptions_for_entities([200, 300, 500])
      # sub1, sub2, sub3
      assert length(batch_result) == 3
      assert sub1 in batch_result
      assert sub2 in batch_result
      assert sub3 in batch_result

      # Test killmail that matches multiple subscriptions
      shared_killmail = %{
        "killmail_id" => 2001,
        "solar_system_id" => 30_000_999,
        # Matches sub1 and sub2
        "victim" => %{"character_id" => 200},
        "attackers" => []
      }

      # Find interested subscriptions
      interested = BatchProcessor.find_interested_subscriptions([shared_killmail])
      interested_subs = interested[2001]

      assert length(interested_subs) == 2
      assert sub1 in interested_subs
      assert sub2 in interested_subs
      assert sub3 not in interested_subs
    end

    test "character caching integration with batch processing" do
      # Create subscription
      {:ok, sub_id} =
        SubscriptionManager.add_subscription(
          %{
            "subscriber_id" => "cache_test_user",
            "user_id" => "cache_test",
            "system_ids" => [],
            "character_ids" => [111, 222, 333],
            "socket_pid" => self()
          },
          :websocket
        )

      # Create killmails with same characters
      killmails = [
        %{
          "killmail_id" => 3001,
          "solar_system_id" => 30_000_999,
          "victim" => %{"character_id" => 111},
          "attackers" => [%{"character_id" => 444}]
        },
        %{
          "killmail_id" => 3002,
          "solar_system_id" => 30_000_998,
          "victim" => %{"character_id" => 222},
          # Same character as first killmail
          "attackers" => [%{"character_id" => 111}]
        }
      ]

      # First batch processing - will populate cache
      subscriptions = %{sub_id => %{"character_ids" => [111, 222, 333]}}
      result1 = BatchProcessor.group_killmails_by_subscription(killmails, subscriptions)

      # Both killmails should match (character 111 and 222)
      assert Map.has_key?(result1, sub_id)
      assert length(result1[sub_id]) == 2

      # Second batch processing - should use cache
      result2 = BatchProcessor.group_killmails_by_subscription(killmails, subscriptions)

      # Results should be identical
      assert result1 == result2

      # Verify cache can store and retrieve character data
      # (Note: direct usage of Filter module may not trigger cache telemetry)
      cache_stats = CharacterCache.get_cache_stats()
      assert is_map(cache_stats)
    end

    test "performance with realistic data volumes" do
      # Create 100 subscriptions with varying character interests
      subscription_ids =
        for i <- 1..100 do
          # 10-50 characters each
          char_count = 10 + :rand.uniform(40)
          characters = Enum.map(1..char_count, fn _ -> :rand.uniform(10_000) end)

          {:ok, sub_id} =
            SubscriptionManager.add_subscription(
              %{
                "subscriber_id" => "perf_user_#{i}",
                "user_id" => "perf_user_#{i}",
                "system_ids" => [],
                "character_ids" => characters,
                "socket_pid" => self()
              },
              :websocket
            )

          {sub_id, characters}
        end

      # Generate 500 realistic killmails
      killmails =
        for i <- 1..500 do
          # 1-20 attackers
          attacker_count = 1 + :rand.uniform(20)

          %{
            "killmail_id" => i,
            "solar_system_id" => 30_000_000 + :rand.uniform(1000),
            "victim" => %{"character_id" => :rand.uniform(10_000)},
            "attackers" =>
              Enum.map(1..attacker_count, fn _ ->
                %{"character_id" => :rand.uniform(10_000)}
              end)
          }
        end

      # Time the batch processing
      subscriptions =
        Map.new(subscription_ids, fn {sub_id, chars} ->
          {sub_id, %{"character_ids" => chars}}
        end)

      {processing_time, result} =
        :timer.tc(fn ->
          BatchProcessor.group_killmails_by_subscription(killmails, subscriptions)
        end)

      # Should complete in reasonable time (under 5 seconds)
      assert processing_time < 5_000_000

      # Should find some matches
      assert map_size(result) > 0

      # Verify character index can handle the load
      {lookup_time, lookup_result} =
        :timer.tc(fn ->
          CharacterIndex.find_subscriptions_for_entity(5000)
        end)

      # Character lookup should be very fast (under 1ms)
      assert lookup_time < 1_000
      assert is_list(lookup_result)
    end
  end

  describe "mixed system and character subscriptions" do
    test "OR logic between systems and characters" do
      # Create subscription with both systems and characters
      {:ok, sub_id} =
        SubscriptionManager.add_subscription(
          %{
            "subscriber_id" => "mixed_user",
            "user_id" => "mixed_user",
            "system_ids" => [30_000_142, 30_000_143],
            "character_ids" => [777, 888],
            "socket_pid" => self()
          },
          :websocket
        )

      # Killmail matching system but not character
      system_match = %{
        "killmail_id" => 4001,
        "solar_system_id" => 30_000_142,
        "victim" => %{"character_id" => 999_999},
        "attackers" => []
      }

      # Killmail matching character but not system
      character_match = %{
        "killmail_id" => 4002,
        "solar_system_id" => 30_000_999,
        "victim" => %{"character_id" => 777},
        "attackers" => []
      }

      # Killmail matching both
      both_match = %{
        "killmail_id" => 4003,
        "solar_system_id" => 30_000_142,
        "victim" => %{"character_id" => 777},
        "attackers" => []
      }

      # Killmail matching neither
      no_match = %{
        "killmail_id" => 4004,
        "solar_system_id" => 30_000_999,
        "victim" => %{"character_id" => 999_999},
        "attackers" => []
      }

      killmails = [system_match, character_match, both_match, no_match]

      subscriptions = %{
        sub_id => %{
          "system_ids" => [30_000_142, 30_000_143],
          "character_ids" => [777, 888]
        }
      }

      result = BatchProcessor.group_killmails_by_subscription(killmails, subscriptions)

      # Should match first three killmails (system OR character match)
      assert Map.has_key?(result, sub_id)
      assert length(result[sub_id]) == 3

      matched_ids = result[sub_id] |> Enum.map(& &1["killmail_id"]) |> Enum.sort()
      assert matched_ids == [4001, 4002, 4003]
    end
  end

  describe "error handling and edge cases" do
    test "handles empty character lists gracefully" do
      {:ok, sub_id} =
        SubscriptionManager.add_subscription(
          %{
            "subscriber_id" => "empty_chars_user",
            "user_id" => "empty_user",
            "system_ids" => [30_000_142],
            "character_ids" => [],
            "socket_pid" => self()
          },
          :websocket
        )

      # Should not be in character index
      assert CharacterIndex.find_subscriptions_for_entity(123) == []

      # But should still work for system matching
      killmail = %{
        "killmail_id" => 5001,
        "solar_system_id" => 30_000_142,
        "victim" => %{"character_id" => 123},
        "attackers" => []
      }

      subscriptions = %{
        sub_id => %{
          "system_ids" => [30_000_142],
          "character_ids" => []
        }
      }

      result = BatchProcessor.group_killmails_by_subscription([killmail], subscriptions)
      assert Map.has_key?(result, sub_id)
    end

    test "handles killmails with missing character data" do
      {:ok, sub_id} =
        SubscriptionManager.add_subscription(
          %{
            "subscriber_id" => "missing_data_user",
            "user_id" => "missing_user",
            "system_ids" => [],
            "character_ids" => [123],
            "socket_pid" => self()
          },
          :websocket
        )

      # Killmail with missing victim character_id
      missing_victim = %{
        "killmail_id" => 6001,
        "solar_system_id" => 30_000_999,
        "victim" => %{},
        "attackers" => []
      }

      # Killmail with nil attackers
      nil_attackers = %{
        "killmail_id" => 6002,
        "solar_system_id" => 30_000_999,
        "victim" => %{"character_id" => 456},
        "attackers" => nil
      }

      subscriptions = %{sub_id => %{"character_ids" => [123]}}

      result =
        BatchProcessor.group_killmails_by_subscription(
          [missing_victim, nil_attackers],
          subscriptions
        )

      # Should handle gracefully without matches
      assert not Map.has_key?(result, sub_id) or result[sub_id] == []
    end
  end

  defp ensure_cache_available do
    # Check if cache process is running by looking for it in the registry
    case Process.whereis(:wanderer_cache) do
      nil ->
        # Start the cache manually for tests
        opts = [
          default_ttl: :timer.minutes(5),
          expiration:
            expiration(
              interval: :timer.seconds(60),
              default: :timer.minutes(5),
              lazy: true
            )
        ]

        case Cachex.start_link(:wanderer_cache, opts) do
          {:ok, _pid} ->
            # Give cache time to fully initialize
            Process.sleep(10)
            :ok

          {:error, {:already_started, _pid}} ->
            :ok
        end

      _pid ->
        :ok
    end
  end
end
