defmodule WandererKills.Benchmarks.BatchProcessorBenchmark do
  @moduledoc """
  Benchmarks for the batch processor with realistic data volumes.

  Run with: mix run bench/batch_processor_benchmark.exs
  """

  alias WandererKills.Ingest.Killmails.BatchProcessor
  alias WandererKills.Subs.Subscriptions.CharacterIndex
  alias WandererKills.Core.Observability.BatchTelemetry

  require Logger

  def run do
    Logger.info("Starting Batch Processor Benchmarks...")

    # Ensure telemetry handlers are attached
    BatchTelemetry.attach_handlers()

    # Start the application to ensure CharacterIndex is running
    Application.ensure_all_started(:wanderer_kills)

    # Clean up any existing data
    CharacterIndex.clear()

    # Run benchmarks
    benchmark_character_extraction()
    benchmark_subscription_matching()
    benchmark_character_index_performance()
    benchmark_realistic_scenario()

    Logger.info("Benchmarks completed!")
  end

  defp benchmark_character_extraction do
    Logger.info("\n=== Character Extraction Benchmark ===")

    # Small batch (10 killmails)
    small_batch = generate_killmails(10, 5)

    {time_small, _} =
      :timer.tc(fn ->
        BatchProcessor.extract_all_characters(small_batch)
      end)

    Logger.info("Small batch (10 killmails): #{time_small / 1000}ms")

    # Medium batch (100 killmails)
    medium_batch = generate_killmails(100, 10)

    {time_medium, _} =
      :timer.tc(fn ->
        BatchProcessor.extract_all_characters(medium_batch)
      end)

    Logger.info("Medium batch (100 killmails): #{time_medium / 1000}ms")

    # Large batch (1000 killmails)
    large_batch = generate_killmails(1000, 15)

    {time_large, _} =
      :timer.tc(fn ->
        BatchProcessor.extract_all_characters(large_batch)
      end)

    Logger.info("Large batch (1000 killmails): #{time_large / 1000}ms")

    # Extra large batch (5000 killmails)
    xl_batch = generate_killmails(5000, 20)

    {time_xl, _} =
      :timer.tc(fn ->
        BatchProcessor.extract_all_characters(xl_batch)
      end)

    Logger.info("Extra large batch (5000 killmails): #{time_xl / 1000}ms")
  end

  defp benchmark_subscription_matching do
    Logger.info("\n=== Subscription Matching Benchmark ===")

    # Generate test data
    killmails = generate_killmails(500, 10)

    # Small subscription set (10 subscriptions)
    small_subs = generate_subscription_map(10, 50)

    {time_small, _} =
      :timer.tc(fn ->
        BatchProcessor.match_killmails_to_subscriptions(killmails, small_subs)
      end)

    Logger.info("500 killmails x 10 subscriptions: #{time_small / 1000}ms")

    # Medium subscription set (100 subscriptions)
    medium_subs = generate_subscription_map(100, 100)

    {time_medium, _} =
      :timer.tc(fn ->
        BatchProcessor.match_killmails_to_subscriptions(killmails, medium_subs)
      end)

    Logger.info("500 killmails x 100 subscriptions: #{time_medium / 1000}ms")

    # Large subscription set (1000 subscriptions)
    large_subs = generate_subscription_map(1000, 200)

    {time_large, _} =
      :timer.tc(fn ->
        BatchProcessor.match_killmails_to_subscriptions(killmails, large_subs)
      end)

    Logger.info("500 killmails x 1000 subscriptions: #{time_large / 1000}ms")
  end

  defp benchmark_character_index_performance do
    Logger.info("\n=== Character Index Performance Benchmark ===")

    # Clear and populate index with many subscriptions
    CharacterIndex.clear()

    # Add 10,000 subscriptions with various character interests
    Logger.info("Populating CharacterIndex with 10,000 subscriptions...")

    {populate_time, _} =
      :timer.tc(fn ->
        for i <- 1..10_000 do
          characters = Enum.to_list((i * 10)..(i * 10 + :rand.uniform(20)))
          CharacterIndex.add_subscription("sub_#{i}", characters)
        end
      end)

    Logger.info("Population time: #{populate_time / 1000}ms")

    # Benchmark lookups
    test_characters = Enum.map(1..100, fn _ -> :rand.uniform(100_000) end)

    {lookup_time, _} =
      :timer.tc(fn ->
        Enum.each(test_characters, fn char_id ->
          CharacterIndex.find_subscriptions_for_entity(char_id)
        end)
      end)

    Logger.info("100 single character lookups: #{lookup_time / 1000}ms")

    # Benchmark batch lookup
    {batch_lookup_time, _} =
      :timer.tc(fn ->
        CharacterIndex.find_subscriptions_for_entities(test_characters)
      end)

    Logger.info("Batch lookup of 100 characters: #{batch_lookup_time / 1000}ms")
  end

  defp benchmark_realistic_scenario do
    Logger.info("\n=== Realistic Scenario Benchmark ===")

    Logger.info(
      "Simulating a busy system with 1000 active subscriptions and incoming killmail batches"
    )

    # Clear and set up realistic subscriptions
    CharacterIndex.clear()

    # Create 1000 subscriptions with varied character interests
    Logger.info("Setting up 1000 subscriptions...")

    subscriptions =
      for i <- 1..1000 do
        # Each subscription interested in 10-50 characters
        char_count = 10 + :rand.uniform(40)
        characters = Enum.map(1..char_count, fn _ -> :rand.uniform(1_000_000) end)
        CharacterIndex.add_subscription("sub_#{i}", characters)
        {"sub_#{i}", %{"id" => "sub_#{i}", "character_ids" => characters}}
      end
      |> Map.new()

    # Simulate processing batches of killmails
    batch_sizes = [50, 100, 200, 500]

    Enum.each(batch_sizes, fn batch_size ->
      killmails = generate_realistic_killmails(batch_size)

      {total_time, result} =
        :timer.tc(fn ->
          BatchProcessor.group_killmails_by_subscription(killmails, subscriptions)
        end)

      matched_subs = map_size(result)
      total_matches = result |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

      Logger.info("""
      Batch size: #{batch_size} killmails
        Processing time: #{total_time / 1000}ms
        Matched subscriptions: #{matched_subs}
        Total killmail-subscription matches: #{total_matches}
        Avg time per killmail: #{Float.round(total_time / 1000 / batch_size, 2)}ms
      """)
    end)
  end

  # Helper functions to generate test data

  defp generate_killmails(count, attackers_per_kill) do
    for i <- 1..count do
      %{
        "killmail_id" => i,
        "victim" => %{"character_id" => :rand.uniform(1_000_000)},
        "attackers" =>
          Enum.map(1..attackers_per_kill, fn _ ->
            %{"character_id" => :rand.uniform(1_000_000)}
          end)
      }
    end
  end

  defp generate_realistic_killmails(count) do
    # Generate killmails with realistic distributions
    # Some solo kills, some small gang, some large fleet
    for i <- 1..count do
      attacker_count =
        case :rand.uniform(100) do
          # 20% solo
          n when n <= 20 -> 1
          # 30% small gang
          n when n <= 50 -> 2 + :rand.uniform(5)
          # 30% medium fleet
          n when n <= 80 -> 10 + :rand.uniform(20)
          # 20% large fleet
          _ -> 50 + :rand.uniform(200)
        end

      %{
        "killmail_id" => i,
        "solar_system_id" => 30_000_000 + :rand.uniform(5000),
        "victim" => %{
          "character_id" => :rand.uniform(1_000_000),
          "corporation_id" => :rand.uniform(100_000),
          "alliance_id" => if(:rand.uniform(100) > 30, do: :rand.uniform(10_000), else: nil)
        },
        "attackers" =>
          Enum.map(1..attacker_count, fn _ ->
            %{
              "character_id" => :rand.uniform(1_000_000),
              "corporation_id" => :rand.uniform(100_000),
              "alliance_id" => if(:rand.uniform(100) > 30, do: :rand.uniform(10_000), else: nil)
            }
          end),
        "killmail_time" => DateTime.utc_now()
      }
    end
  end

  defp generate_subscription_map(count, chars_per_sub) do
    for i <- 1..count do
      characters = Enum.map(1..chars_per_sub, fn _ -> :rand.uniform(1_000_000) end)
      {"sub_#{i}", characters}
    end
    |> Map.new()
  end
end

# Run the benchmarks
WandererKills.Benchmarks.BatchProcessorBenchmark.run()
