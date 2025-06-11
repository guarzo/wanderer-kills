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
    if websocket_connected?() do
      "online"
    else
      "offline"
    end
  end

  @doc """
  Get the last killmail time from the system.
  """
  @spec get_last_killmail_time() :: String.t() | nil
  def get_last_killmail_time do
    # Get the most recent killmail from the ETS table
    # Note: This scans the entire table, so it may be inefficient for large datasets
    case get_latest_killmail_from_ets() do
      {_killmail_id, killmail_data} when is_map(killmail_data) ->
        killmail_data["kill_time"] || killmail_data["killmail_time"]

      _ ->
        nil
    end
  end

  defp get_latest_killmail_from_ets do
    # Scan the killmails ETS table to find the most recent one
    # In production, you might want to maintain a separate index for this
    :ets.foldl(
      fn {killmail_id, killmail_data}, acc ->
        compare_and_select_latest_killmail({killmail_id, killmail_data}, acc)
      end,
      {nil, %{}},
      :killmails
    )
  end

  defp compare_and_select_latest_killmail({killmail_id, killmail_data}, acc) do
    current_time = get_time_from_killmail(killmail_data)
    acc_time = get_time_from_killmail(elem(acc, 1))

    case {current_time, acc_time} do
      {time1, time2} when is_binary(time1) and is_binary(time2) ->
        if time1 > time2, do: {killmail_id, killmail_data}, else: acc

      {time1, _} when is_binary(time1) ->
        {killmail_id, killmail_data}

      _ ->
        acc
    end
  rescue
    _ -> {nil, %{}}
  end

  defp get_time_from_killmail(%{"kill_time" => time}) when is_binary(time), do: time
  defp get_time_from_killmail(%{"killmail_time" => time}) when is_binary(time), do: time
  defp get_time_from_killmail(_), do: nil

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
    case Cachex.stats(:wanderer_cache) do
      {:ok, stats} ->
        hit_rate = calculate_hit_rate(stats)

        %{
          status: determine_cache_status(hit_rate),
          message: format_cache_message(hit_rate, stats),
          hit_rate: hit_rate,
          size: Map.get(stats, :calls, %{}) |> Map.get(:set, 0)
        }

      {:error, _} ->
        %{
          status: "error",
          message: "Unable to retrieve cache statistics"
        }
    end
  end

  defp calculate_hit_rate(%{calls: %{get: gets, set: _sets}} = stats) when gets > 0 do
    hits = Map.get(stats, :hits, %{}) |> Map.get(:get, 0)
    Float.round(hits / gets * 100, 2)
  end

  defp calculate_hit_rate(_), do: 0.0

  defp determine_cache_status(hit_rate) do
    cond do
      hit_rate >= 80 -> "operational"
      hit_rate >= 50 -> "degraded"
      true -> "warning"
    end
  end

  defp format_cache_message(hit_rate, _stats) do
    "Cache hit rate: #{hit_rate}%"
  end

  defp websocket_connected? do
    Process.whereis(WandererKillsWeb.Endpoint) != nil
  end
end
