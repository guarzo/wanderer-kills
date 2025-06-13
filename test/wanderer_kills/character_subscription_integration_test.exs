defmodule WandererKills.CharacterSubscriptionIntegrationTest do
  @moduledoc """
  Integration tests for character-based subscription functionality.

  Tests the full flow from subscription creation through killmail filtering
  to ensure character-based subscriptions work correctly across all components.
  """

  use ExUnit.Case, async: false
  use WandererKills.Test.SharedContexts

  alias WandererKills.SubscriptionManager
  alias WandererKills.Storage.KillmailStore

  setup do
    # Ensure cache is available
    ensure_cache_available()

    # Clear any existing data
    :ok = Application.stop(:wanderer_kills)
    :ok = Application.start(:wanderer_kills)

    # Ensure cache is available after restart
    ensure_cache_available()

    # Wait for services to start
    Process.sleep(100)

    :ok
  end

  describe "character-based webhook subscriptions" do
    test "filters killmails correctly for character subscriptions" do
      # Create a subscription for specific characters
      {:ok, subscription_id} =
        SubscriptionManager.add_subscription(%{
          "subscriber_id" => "test_user",
          "system_ids" => [],
          "character_ids" => [95_465_499, 90_379_338],
          "callback_url" => "https://example.com/webhook"
        })

      assert is_binary(subscription_id)

      # Create test killmails
      killmail_with_victim_match = %{
        "killmail_id" => 123_456,
        "solar_system_id" => 30_000_999,
        "kill_time" => "2024-01-01T12:00:00Z",
        "victim" => %{
          # Matches subscription
          "character_id" => 95_465_499,
          "corporation_id" => 98_000_001,
          "ship_type_id" => 587
        },
        "attackers" => [
          %{"character_id" => 111_111, "ship_type_id" => 621}
        ],
        "zkb" => %{"totalValue" => 10_000_000}
      }

      killmail_with_attacker_match = %{
        "killmail_id" => 123_457,
        "solar_system_id" => 30_000_888,
        "kill_time" => "2024-01-01T12:01:00Z",
        "victim" => %{
          "character_id" => 222_222,
          "corporation_id" => 98_000_002,
          "ship_type_id" => 590
        },
        "attackers" => [
          %{"character_id" => 333_333, "ship_type_id" => 622},
          # Matches subscription
          %{"character_id" => 90_379_338, "ship_type_id" => 623}
        ],
        "zkb" => %{"totalValue" => 20_000_000}
      }

      killmail_no_match = %{
        "killmail_id" => 123_458,
        "solar_system_id" => 30_000_777,
        "kill_time" => "2024-01-01T12:02:00Z",
        "victim" => %{
          "character_id" => 444_444,
          "corporation_id" => 98_000_003,
          "ship_type_id" => 591
        },
        "attackers" => [
          %{"character_id" => 555_555, "ship_type_id" => 624}
        ],
        "zkb" => %{"totalValue" => 30_000_000}
      }

      # Store killmails
      :ok = KillmailStore.store_killmail(killmail_with_victim_match)
      :ok = KillmailStore.store_killmail(killmail_with_attacker_match)
      :ok = KillmailStore.store_killmail(killmail_no_match)

      # Verify subscription matching
      subscriptions = SubscriptionManager.list_subscriptions()
      assert length(subscriptions) == 1

      [sub] = subscriptions
      # Character IDs are sorted in the subscription
      assert Enum.sort(sub["character_ids"]) == Enum.sort([90_379_338, 95_465_499])

      # Verify the Filter module correctly identifies matching killmails
      alias WandererKills.Subscriptions.Filter

      assert Filter.matches_subscription?(killmail_with_victim_match, sub)
      assert Filter.matches_subscription?(killmail_with_attacker_match, sub)
      refute Filter.matches_subscription?(killmail_no_match, sub)
    end

    test "handles mixed system and character subscriptions" do
      # Create a subscription with both systems and characters
      {:ok, _subscription_id} =
        SubscriptionManager.add_subscription(%{
          "subscriber_id" => "test_user",
          "system_ids" => [30_000_142],
          "character_ids" => [95_465_499],
          "callback_url" => "https://example.com/webhook"
        })

      # Killmail matching by system only
      killmail_system_match = %{
        "killmail_id" => 200_001,
        # Matches system
        "solar_system_id" => 30_000_142,
        "kill_time" => "2024-01-01T12:00:00Z",
        "victim" => %{
          # Does not match character
          "character_id" => 999_999,
          "corporation_id" => 98_000_001,
          "ship_type_id" => 587
        },
        "attackers" => [],
        "zkb" => %{"totalValue" => 1_000_000}
      }

      # Killmail matching by character only
      killmail_character_match = %{
        "killmail_id" => 200_002,
        # Does not match system
        "solar_system_id" => 30_000_999,
        "kill_time" => "2024-01-01T12:01:00Z",
        "victim" => %{
          # Matches character
          "character_id" => 95_465_499,
          "corporation_id" => 98_000_002,
          "ship_type_id" => 590
        },
        "attackers" => [],
        "zkb" => %{"totalValue" => 2_000_000}
      }

      # Killmail matching both
      killmail_both_match = %{
        "killmail_id" => 200_003,
        # Matches system
        "solar_system_id" => 30_000_142,
        "kill_time" => "2024-01-01T12:02:00Z",
        "victim" => %{
          # Matches character
          "character_id" => 95_465_499,
          "corporation_id" => 98_000_003,
          "ship_type_id" => 591
        },
        "attackers" => [],
        "zkb" => %{"totalValue" => 3_000_000}
      }

      # Killmail matching neither
      killmail_no_match = %{
        "killmail_id" => 200_004,
        # Does not match system
        "solar_system_id" => 30_000_888,
        "kill_time" => "2024-01-01T12:03:00Z",
        "victim" => %{
          # Does not match character
          "character_id" => 888_888,
          "corporation_id" => 98_000_004,
          "ship_type_id" => 592
        },
        "attackers" => [],
        "zkb" => %{"totalValue" => 4_000_000}
      }

      # Verify filtering
      [sub] = SubscriptionManager.list_subscriptions()
      alias WandererKills.Subscriptions.Filter

      assert Filter.matches_subscription?(killmail_system_match, sub)
      assert Filter.matches_subscription?(killmail_character_match, sub)
      assert Filter.matches_subscription?(killmail_both_match, sub)
      refute Filter.matches_subscription?(killmail_no_match, sub)
    end
  end

  describe "performance with large character lists" do
    test "efficiently handles subscriptions with many characters" do
      # Create a subscription with 1000 characters
      character_ids = Enum.to_list(1..1000)

      {:ok, _subscription_id} =
        SubscriptionManager.add_subscription(%{
          "subscriber_id" => "test_user",
          "system_ids" => [],
          "character_ids" => character_ids,
          "callback_url" => "https://example.com/webhook"
        })

      # Create a killmail with many attackers
      killmail = %{
        "killmail_id" => 300_001,
        "solar_system_id" => 30_000_142,
        "kill_time" => "2024-01-01T12:00:00Z",
        "victim" => %{
          "character_id" => 9_999_999,
          "corporation_id" => 98_000_001,
          "ship_type_id" => 587
        },
        "attackers" =>
          Enum.map(1001..2000, fn id ->
            %{"character_id" => id, "ship_type_id" => 621}
          end),
        "zkb" => %{"totalValue" => 100_000_000}
      }

      # Add one matching attacker
      killmail_with_match =
        put_in(
          killmail,
          ["attackers", Access.at(500), "character_id"],
          # This character is in our subscription
          500
        )

      [sub] = SubscriptionManager.list_subscriptions()
      alias WandererKills.Subscriptions.Filter

      # Time the filtering operation
      {time, result} =
        :timer.tc(fn ->
          Filter.matches_subscription?(killmail_with_match, sub)
        end)

      assert result == true
      # Should complete in under 10ms even with 1000 characters and 1000 attackers
      # microseconds
      assert time < 10_000
    end
  end
end
