defmodule WandererKills.Core.Observability.BatchTelemetry do
  @moduledoc """
  Telemetry handler for batch processing operations.

  Attaches handlers to track performance metrics for character-based
  batch processing operations.
  """

  require Logger

  @events [
    [:wanderer_kills, :batch_processor, :extract_characters],
    [:wanderer_kills, :batch_processor, :match_killmails],
    [:wanderer_kills, :batch_processor, :find_subscriptions],
    [:wanderer_kills, :batch_processor, :group_killmails],
    [:wanderer_kills, :character_cache, :hit],
    [:wanderer_kills, :character_cache, :miss],
    [:wanderer_kills, :character_cache, :batch]
  ]

  def attach_handlers do
    :telemetry.attach_many(
      "wanderer-kills-batch-telemetry",
      @events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event(
        [:wanderer_kills, :batch_processor, :extract_characters],
        measurements,
        metadata,
        _config
      ) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    chars_per_killmail =
      if measurements.killmail_count > 0 do
        measurements.character_count / measurements.killmail_count
      else
        0.0
      end

    Logger.info("Batch character extraction completed",
      duration_ms: duration_ms,
      killmail_count: measurements.killmail_count,
      character_count: measurements.character_count,
      avg_chars_per_killmail: Float.round(chars_per_killmail, 2),
      operation: metadata.operation
    )
  end

  def handle_event(
        [:wanderer_kills, :batch_processor, :match_killmails],
        measurements,
        metadata,
        _config
      ) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    match_rate =
      if measurements.killmail_count > 0 do
        measurements.match_count / measurements.killmail_count * 100
      else
        0.0
      end

    Logger.info("Batch killmail matching completed",
      duration_ms: duration_ms,
      killmail_count: measurements.killmail_count,
      subscription_count: measurements.subscription_count,
      match_count: measurements.match_count,
      matched_subscription_count: measurements.matched_subscription_count,
      match_rate_percent: Float.round(match_rate, 2),
      operation: metadata.operation
    )
  end

  def handle_event(
        [:wanderer_kills, :batch_processor, :find_subscriptions],
        measurements,
        metadata,
        _config
      ) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    hit_rate =
      if measurements.killmail_count > 0 do
        measurements.matched_killmail_count / measurements.killmail_count * 100
      else
        0.0
      end

    avg_subs_per_match =
      if measurements.matched_killmail_count > 0 do
        measurements.total_subscription_matches / measurements.matched_killmail_count
      else
        0.0
      end

    Logger.info("Batch subscription lookup completed",
      duration_ms: duration_ms,
      killmail_count: measurements.killmail_count,
      matched_killmail_count: measurements.matched_killmail_count,
      total_subscription_matches: measurements.total_subscription_matches,
      hit_rate_percent: Float.round(hit_rate, 2),
      avg_subscriptions_per_match: Float.round(avg_subs_per_match, 2),
      operation: metadata.operation
    )
  end

  def handle_event(
        [:wanderer_kills, :batch_processor, :group_killmails],
        measurements,
        metadata,
        _config
      ) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    avg_killmails_per_sub =
      if measurements.grouped_subscription_count > 0 do
        measurements.total_grouped_killmails / measurements.grouped_subscription_count
      else
        0.0
      end

    Logger.info("Batch killmail grouping completed",
      duration_ms: duration_ms,
      killmail_count: measurements.killmail_count,
      subscription_count: measurements.subscription_count,
      grouped_subscription_count: measurements.grouped_subscription_count,
      total_grouped_killmails: measurements.total_grouped_killmails,
      avg_killmails_per_subscription: Float.round(avg_killmails_per_sub, 2),
      operation: metadata.operation
    )
  end

  @doc """
  Detaches all telemetry handlers.
  """
  def handle_event(
        [:wanderer_kills, :character_cache, :hit],
        measurements,
        metadata,
        _config
      ) do
    Logger.debug("Character cache hit",
      killmail_id: metadata.killmail_id,
      count: measurements.count
    )
  end

  def handle_event(
        [:wanderer_kills, :character_cache, :miss],
        measurements,
        metadata,
        _config
      ) do
    Logger.debug("Character cache miss",
      killmail_id: metadata.killmail_id,
      count: measurements.count
    )
  end

  def handle_event(
        [:wanderer_kills, :character_cache, :batch],
        measurements,
        _metadata,
        _config
      ) do
    hit_rate =
      if measurements.total > 0 do
        measurements.hits / measurements.total * 100
      else
        0.0
      end

    Logger.info("Character cache batch operation completed",
      hits: measurements.hits,
      misses: measurements.misses,
      total: measurements.total,
      hit_rate_percent: Float.round(hit_rate, 2)
    )
  end

  def detach_handlers do
    :telemetry.detach("wanderer-kills-batch-telemetry")
  end
end
