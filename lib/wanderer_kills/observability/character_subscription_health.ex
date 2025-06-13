defmodule WandererKills.Observability.CharacterSubscriptionHealth do
  @moduledoc """
  Health check module for character subscription functionality.

  This module provides health checks and metrics for:
  - Character subscription counts and distribution
  - Character index performance and size
  - Character cache performance
  - Subscription manager status
  """

  require Logger
  alias WandererKills.Support.Clock
  alias WandererKills.Observability.HealthCheckBehaviour
  alias WandererKills.SubscriptionManager
  alias WandererKills.Subscriptions.CharacterIndex
  alias WandererKills.Killmails.CharacterCache

  @behaviour HealthCheckBehaviour

  @impl true
  def check_health(_opts \\ []) do
    try do
      # Check if critical components are running
      subscription_manager_health = check_subscription_manager()
      character_index_health = check_character_index()
      character_cache_health = check_character_cache()

      # Determine overall health
      all_healthy =
        subscription_manager_health.healthy and
          character_index_health.healthy and
          character_cache_health.healthy

      status = if all_healthy, do: "ok", else: "degraded"

      %{
        healthy: all_healthy,
        status: status,
        details: %{
          component: "character_subscriptions",
          subscription_manager: subscription_manager_health,
          character_index: character_index_health,
          character_cache: character_cache_health
        },
        timestamp: Clock.now_iso8601()
      }
    rescue
      error ->
        Logger.error("Character subscription health check failed: #{inspect(error)}")

        %{
          healthy: false,
          status: "error",
          details: %{
            component: "character_subscriptions",
            error: "Health check failed",
            reason: inspect(error)
          },
          timestamp: Clock.now_iso8601()
        }
    end
  end

  @impl true
  def get_metrics(_opts \\ []) do
    try do
      subscription_metrics = get_subscription_metrics()
      index_metrics = get_character_index_metrics()
      cache_metrics = get_character_cache_metrics()

      %{
        component: "character_subscriptions",
        timestamp: Clock.now_iso8601(),
        metrics: %{
          subscriptions: subscription_metrics,
          character_index: index_metrics,
          character_cache: cache_metrics
        }
      }
    rescue
      error ->
        Logger.error("Character subscription metrics collection failed: #{inspect(error)}")

        %{
          component: "character_subscriptions",
          timestamp: Clock.now_iso8601(),
          metrics: %{
            error: "Metrics collection failed",
            reason: inspect(error)
          }
        }
    end
  end

  @impl true
  def default_config do
    [
      timeout_ms: 5_000
    ]
  end

  # Private helper functions

  defp check_subscription_manager do
    case Process.whereis(SubscriptionManager) do
      nil ->
        %{
          healthy: false,
          status: "error",
          details: %{error: "SubscriptionManager process not found"}
        }

      pid when is_pid(pid) ->
        try do
          stats = SubscriptionManager.get_stats()

          %{
            healthy: true,
            status: "ok",
            details: %{
              process_alive: true,
              total_subscriptions:
                stats.http_subscription_count + stats.websocket_subscription_count,
              character_subscriptions: stats.total_subscribed_characters > 0
            }
          }
        rescue
          error ->
            %{
              healthy: false,
              status: "error",
              details: %{error: "Failed to get subscription stats", reason: inspect(error)}
            }
        end
    end
  end

  defp check_character_index do
    case Process.whereis(CharacterIndex) do
      nil ->
        %{
          healthy: false,
          status: "error",
          details: %{error: "CharacterIndex process not found"}
        }

      pid when is_pid(pid) ->
        try do
          stats = CharacterIndex.get_stats()

          # Consider healthy if index is responding and has reasonable size
          # 1M character entries max
          index_size_ok = stats.total_character_entries < 1_000_000

          %{
            healthy: index_size_ok,
            status: if(index_size_ok, do: "ok", else: "warning"),
            details: %{
              process_alive: true,
              total_subscriptions: stats.total_subscriptions,
              total_character_entries: stats.total_character_entries,
              index_size_acceptable: index_size_ok
            }
          }
        rescue
          error ->
            %{
              healthy: false,
              status: "error",
              details: %{error: "Failed to get character index stats", reason: inspect(error)}
            }
        end
    end
  end

  defp check_character_cache do
    try do
      cache_stats = CharacterCache.get_cache_stats()

      # Cache is healthy if it's responding
      %{
        healthy: true,
        status: "ok",
        details: %{
          cache_responding: true,
          stats_available: is_map(cache_stats)
        }
      }
    rescue
      error ->
        %{
          healthy: false,
          # Cache issues are not critical
          status: "warning",
          details: %{error: "Failed to get character cache stats", reason: inspect(error)}
        }
    end
  end

  defp get_subscription_metrics do
    try do
      stats = SubscriptionManager.get_stats()

      %{
        total_subscriptions: stats.http_subscription_count + stats.websocket_subscription_count,
        http_subscriptions: stats.http_subscription_count,
        websocket_subscriptions: stats.websocket_subscription_count,
        total_subscribed_systems: stats.total_subscribed_systems,
        total_subscribed_characters: stats.total_subscribed_characters,
        character_subscription_ratio: calculate_character_ratio(stats)
      }
    rescue
      error ->
        %{error: "Failed to collect subscription metrics", reason: inspect(error)}
    end
  end

  defp get_character_index_metrics do
    try do
      stats = CharacterIndex.get_stats()

      %{
        total_subscriptions_indexed: stats.total_subscriptions,
        total_character_entries: stats.total_character_entries,
        average_characters_per_subscription: calculate_avg_characters_per_sub(stats),
        memory_usage_estimate: estimate_index_memory_usage(stats)
      }
    rescue
      error ->
        %{error: "Failed to collect character index metrics", reason: inspect(error)}
    end
  end

  defp get_character_cache_metrics do
    try do
      cache_stats = CharacterCache.get_cache_stats()

      case cache_stats do
        %{} = stats ->
          %{
            cache_enabled: true,
            cache_stats: stats
          }

        _ ->
          %{cache_enabled: false}
      end
    rescue
      error ->
        %{error: "Failed to collect character cache metrics", reason: inspect(error)}
    end
  end

  defp calculate_character_ratio(stats) do
    total_subs = stats.http_subscription_count + stats.websocket_subscription_count

    if total_subs > 0 do
      with_characters = if stats.total_subscribed_characters > 0, do: 1, else: 0
      Float.round(with_characters / total_subs, 2)
    else
      0.0
    end
  end

  defp calculate_avg_characters_per_sub(stats) do
    if stats.total_subscriptions > 0 do
      Float.round(stats.total_character_entries / stats.total_subscriptions, 1)
    else
      0.0
    end
  end

  defp estimate_index_memory_usage(stats) do
    # Rough estimate: each character entry ~50 bytes, each subscription ~100 bytes
    character_memory = stats.total_character_entries * 50
    subscription_memory = stats.total_subscriptions * 100
    character_memory + subscription_memory
  end
end
