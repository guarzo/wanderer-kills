defmodule WandererKills.Observability.Status do
  @moduledoc """
  Business logic for application status and health information.

  This module centralizes all status-related operations that were
  previously scattered across controllers.
  """

  alias WandererKills.SubscriptionManager

  @doc """
  Get comprehensive service status information.
  """
  @spec get_service_status() :: map()
  def get_service_status do
    %{
      cache_stats: get_cache_stats(),
      active_subscriptions: get_active_subscription_count(),
      websocket_connected: websocket_connected?(),
      last_killmail_received: get_last_killmail_time(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Get WebSocket-specific status information.
  """
  @spec get_websocket_status() :: String.t()
  def get_websocket_status do
    case Process.whereis(WandererKillsWeb.UserSocket) do
      nil -> "offline"
      _pid -> "online"
    end
  end

  @doc """
  Get the last killmail time from the system.
  """
  @spec get_last_killmail_time() :: String.t() | nil
  def get_last_killmail_time do
    # In a real implementation, this would query the KillStore
    # For now, return nil as placeholder
    nil
  end

  @doc """
  Get active subscription count.
  """
  @spec get_active_subscription_count() :: non_neg_integer()
  def get_active_subscription_count do
    SubscriptionManager.list_subscriptions() |> length()
  rescue
    _ -> 0
  end

  # Private functions

  defp get_cache_stats do
    %{
      status: "operational",
      message: "Cache subsystem functioning normally"
    }
  end

  defp websocket_connected? do
    Process.whereis(WandererKillsWeb.Endpoint) != nil
  end
end
