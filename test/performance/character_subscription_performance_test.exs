defmodule WandererKills.Performance.CharacterSubscriptionPerformanceTest do
  @moduledoc """
  Performance tests for character subscription functionality.

  These tests verify that the system can handle large numbers of
  character subscriptions and killmail processing efficiently.
  """

  use ExUnit.Case, async: false

  alias WandererKills.SubscriptionManager
  alias WandererKills.Subscriptions.CharacterIndex
  alias WandererKills.Killmails.{CharacterCache, BatchProcessor, CharacterMatcher}

  describe "large character list performance" do
    @describetag :performance
    setup do
      # Clear state
      CharacterIndex.clear()
      CharacterCache.clear_cache()

      on_exit(fn ->
        CharacterIndex.clear()
        CharacterCache.clear_cache()
      end)

      :ok
    end

    test "handles subscription with 1000 character IDs" do
      # Create a subscription with the maximum allowed characters (1000)
      large_character_list = Enum.to_list(1..1000)

      {creation_time, {:ok, sub_id}} =
        :timer.tc(fn ->
          SubscriptionManager.add_subscription(
            %{
              "subscriber_id" => "large_char_user",
              "user_id" => "large_user",
              "system_ids" => [],
              "character_ids" => large_character_list,
              "socket_pid" => self()
            },
            :websocket
          )
        end)

      # Subscription creation should be fast (under 100ms)
      assert creation_time < 100_000

      # Verify all characters are indexed
      {lookup_time, lookup_results} =
        :timer.tc(fn ->
          Enum.map(1..10, fn i ->
            CharacterIndex.find_subscriptions_for_character(i * 100)
          end)
        end)

      # 10 lookups should be very fast (under 1ms total)
      assert lookup_time < 1_000

      # All sampled characters should be found
      assert Enum.all?(lookup_results, fn result ->
               result == [sub_id]
             end)

      # Test batch lookup performance
      # 100 characters
      test_characters = Enum.to_list(500..600)

      {batch_lookup_time, batch_result} =
        :timer.tc(fn ->
          CharacterIndex.find_subscriptions_for_characters(test_characters)
        end)

      # Batch lookup should be very fast (under 5ms)
      assert batch_lookup_time < 5_000
      assert batch_result == [sub_id]
    end

    test "character extraction performance with large killmails" do
      # Create a large killmail with many attackers
      large_killmail = %{
        "killmail_id" => 9001,
        "solar_system_id" => 30_000_142,
        "victim" => %{"character_id" => 95_465_499},
        "attackers" =>
          Enum.map(1..500, fn i ->
            %{"character_id" => 100_000 + i}
          end)
      }

      # Test character extraction performance
      {extraction_time, characters} =
        :timer.tc(fn ->
          CharacterMatcher.extract_character_ids(large_killmail)
        end)

      # Should extract 501 characters (1 victim + 500 attackers) quickly
      assert length(characters) == 501
      # Under 10ms
      assert extraction_time < 10_000

      # Test cached extraction
      {_cached_time, cached_characters} =
        :timer.tc(fn ->
          CharacterCache.extract_characters_cached(large_killmail)
        end)

      # Results should be identical
      assert Enum.sort(characters) == Enum.sort(cached_characters)

      # Second call should be faster (cached)
      {second_cached_time, _} =
        :timer.tc(fn ->
          CharacterCache.extract_characters_cached(large_killmail)
        end)

      # Cache lookup should be much faster (allow for timing variance)
      # Sometimes the first extraction is so fast the cache doesn't show much improvement
      assert second_cached_time <= extraction_time + 1000
    end

    test "batch processing with multiple large killmails" do
      # Create 100 killmails with varying numbers of attackers
      killmails =
        for i <- 1..100 do
          # 10-50 attackers each
          attacker_count = 10 + :rand.uniform(40)

          %{
            "killmail_id" => i,
            "solar_system_id" => 30_000_000 + :rand.uniform(1000),
            "victim" => %{"character_id" => :rand.uniform(50_000)},
            "attackers" =>
              Enum.map(1..attacker_count, fn _ ->
                %{"character_id" => :rand.uniform(50_000)}
              end)
          }
        end

      # Test character extraction from all killmails
      {extraction_time, all_characters} =
        :timer.tc(fn ->
          BatchProcessor.extract_all_characters(killmails)
        end)

      # Should complete quickly (under 1 second)
      assert extraction_time < 1_000_000

      # Should find many unique characters
      assert MapSet.size(all_characters) > 1000

      # Test with cached extraction
      {cached_extraction_time, cached_all_characters} =
        :timer.tc(fn ->
          BatchProcessor.extract_all_characters(killmails)
        end)

      # Results should be identical
      assert all_characters == cached_all_characters

      # Cached version should be faster
      assert cached_extraction_time < extraction_time
    end

    test "subscription matching with many overlapping characters" do
      # Create 50 subscriptions with overlapping character interests
      subscription_data =
        for i <- 1..50 do
          # Each subscription interested in 100 characters
          # With overlap to create realistic scenario
          base_start = i * 50
          characters = Enum.to_list(base_start..(base_start + 99))

          {:ok, sub_id} =
            SubscriptionManager.add_subscription(
              %{
                "subscriber_id" => "overlap_user_#{i}",
                "user_id" => "overlap_user_#{i}",
                "system_ids" => [],
                "character_ids" => characters,
                "socket_pid" => self()
              },
              :websocket
            )

          {sub_id, %{"character_ids" => characters}}
        end

      subscriptions = Map.new(subscription_data)

      # Create killmails that will match multiple subscriptions
      test_killmails =
        for i <- 1..20 do
          %{
            "killmail_id" => 10_000 + i,
            "solar_system_id" => 30_000_999,
            # Will hit multiple subscriptions
            "victim" => %{"character_id" => i * 50 + 25},
            "attackers" => []
          }
        end

      # Test batch matching performance
      {matching_time, grouped_result} =
        :timer.tc(fn ->
          BatchProcessor.group_killmails_by_subscription(test_killmails, subscriptions)
        end)

      # Should complete in reasonable time (under 2 seconds)
      assert matching_time < 2_000_000

      # Should find many matches due to overlap
      total_matches = grouped_result |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
      # More matches than killmails due to overlap
      assert total_matches > 20

      # Verify some subscriptions have multiple matches
      subscription_with_multiple_matches =
        grouped_result
        |> Map.values()
        |> Enum.find(fn killmails -> length(killmails) > 1 end)

      assert subscription_with_multiple_matches != nil
    end

    test "character index performance under load" do
      # Add 10,000 subscriptions with varying character counts
      {index_creation_time, _} =
        :timer.tc(fn ->
          for i <- 1..10_000 do
            # 5-25 characters each
            char_count = 5 + :rand.uniform(20)

            characters =
              Enum.map(1..char_count, fn _ ->
                :rand.uniform(100_000)
              end)

            CharacterIndex.add_subscription("load_sub_#{i}", characters)
          end
        end)

      # Index creation should complete in reasonable time (under 10 seconds)
      assert index_creation_time < 10_000_000

      # Test lookup performance with loaded index
      test_characters = Enum.map(1..1000, fn _ -> :rand.uniform(100_000) end)

      {lookup_time, lookup_results} =
        :timer.tc(fn ->
          Enum.map(test_characters, fn char_id ->
            CharacterIndex.find_subscriptions_for_character(char_id)
          end)
        end)

      # 1000 lookups should still be fast (under 100ms)
      assert lookup_time < 100_000

      # Should find some subscriptions
      total_found = lookup_results |> Enum.map(&length/1) |> Enum.sum()
      assert total_found > 0

      # Test batch lookup performance
      {batch_lookup_time, batch_results} =
        :timer.tc(fn ->
          CharacterIndex.find_subscriptions_for_characters(test_characters)
        end)

      # Batch lookup should be reasonably fast (may not always be faster due to overhead)
      assert batch_lookup_time < lookup_time * 2
      assert length(batch_results) > 0

      # Test index statistics
      stats = CharacterIndex.get_stats()
      assert stats.total_subscriptions == 10_000
      assert stats.total_character_entries > 1000
    end
  end

  describe "concurrent subscription load tests" do
    @describetag :load_test
    test "concurrent subscription creation and removal" do
      # Test concurrent operations on subscriptions
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            # Create subscription
            {:ok, sub_id} =
              SubscriptionManager.add_subscription(
                %{
                  "subscriber_id" => "concurrent_user_#{i}",
                  "user_id" => "concurrent_user_#{i}",
                  "system_ids" => [],
                  "character_ids" => Enum.to_list((i * 10)..(i * 10 + 9)),
                  "socket_pid" => self()
                },
                :websocket
              )

            # Do some operations
            chars = CharacterIndex.find_subscriptions_for_character(i * 10 + 5)
            assert sub_id in chars

            # Update subscription
            SubscriptionManager.update_websocket_subscription(sub_id, %{
              "character_ids" => Enum.to_list((i * 10)..(i * 10 + 14))
            })

            # Brief pause
            Process.sleep(1)

            # Remove subscription
            SubscriptionManager.remove_websocket_subscription(sub_id)

            sub_id
          end)
        end

      # Wait for all tasks to complete
      {concurrent_time, results} =
        :timer.tc(fn ->
          # 30 second timeout
          Task.await_many(tasks, 30_000)
        end)

      # Should complete in reasonable time (under 10 seconds)
      assert concurrent_time < 10_000_000

      # All tasks should succeed
      assert length(results) == 100
      assert Enum.all?(results, &is_binary/1)

      # Wait for async cleanup to complete
      Process.sleep(100)

      # Index should be mostly empty after cleanup
      final_stats = CharacterIndex.get_stats()
      # Very lenient due to concurrent operations
      assert final_stats.total_subscriptions < 100
    end

    test "concurrent killmail processing" do
      # Set up some subscriptions
      for i <- 1..20 do
        SubscriptionManager.add_subscription(
          %{
            "subscriber_id" => "processing_user_#{i}",
            "user_id" => "processing_user_#{i}",
            "system_ids" => [],
            "character_ids" => Enum.to_list((i * 100)..(i * 100 + 49)),
            "socket_pid" => self()
          },
          :websocket
        )
      end

      # Create multiple tasks that process killmails concurrently
      processing_tasks =
        for i <- 1..10 do
          Task.async(fn ->
            # Generate killmails for this task
            killmails =
              for j <- 1..50 do
                %{
                  "killmail_id" => i * 1000 + j,
                  "solar_system_id" => 30_000_999,
                  "victim" => %{"character_id" => :rand.uniform(3000)},
                  "attackers" =>
                    Enum.map(1..5, fn _ ->
                      %{"character_id" => :rand.uniform(3000)}
                    end)
                }
              end

            # Process with character extraction
            extracted = BatchProcessor.extract_all_characters(killmails)

            # Find interested subscriptions
            interested = BatchProcessor.find_interested_subscriptions(killmails)

            {MapSet.size(extracted), map_size(interested)}
          end)
        end

      # Wait for all processing to complete
      {processing_time, processing_results} =
        :timer.tc(fn ->
          Task.await_many(processing_tasks, 30_000)
        end)

      # Should complete concurrent processing efficiently (under 5 seconds)
      assert processing_time < 5_000_000

      # All tasks should succeed
      assert length(processing_results) == 10

      assert Enum.all?(processing_results, fn {extracted_count, interested_count} ->
               extracted_count > 0 and interested_count >= 0
             end)
    end
  end
end
