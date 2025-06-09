defmodule WandererKills.Client do
  @moduledoc """
  Main client implementation for WandererKills service.

  This module implements the WandererKills.ClientBehaviour and provides
  a unified interface for fetching killmails, managing subscriptions,
  and accessing cached data. It coordinates between the ZKB client,
  cache, and subscription manager.
  """

  @behaviour WandererKills.ClientBehaviour

  require Logger
  alias WandererKills.{SubscriptionManager, Types}
  alias WandererKills.Killmails.ZkbClient
  alias WandererKills.Cache.Helper

  @impl true
  def fetch_system_kills(system_id, since_hours, limit) do
    Logger.debug("Fetching system kills via WandererKills.Client",
      system_id: system_id,
      since_hours: since_hours,
      limit: limit
    )

    case ZkbClient.fetch_system_killmails(system_id, limit, since_hours) do
      {:ok, kills} ->
        # Filter by time window if needed (since ZKB API doesn't support time filtering directly)
        filtered_kills = filter_kills_by_time(kills, since_hours)
        limited_kills = Enum.take(filtered_kills, limit)

        Logger.info("Successfully fetched system kills",
          system_id: system_id,
          total_kills: length(kills),
          filtered_kills: length(filtered_kills),
          returned_kills: length(limited_kills)
        )

        {:ok, limited_kills}

      {:error, reason} ->
        Logger.error("Failed to fetch system kills",
          system_id: system_id,
          since_hours: since_hours,
          limit: limit,
          error: reason
        )

        {:error, reason}
    end
  end

  @impl true
  def fetch_systems_kills(system_ids, since_hours, limit) do
    Logger.debug("Fetching kills for multiple systems",
      system_ids: system_ids,
      since_hours: since_hours,
      limit: limit
    )

    # Batch fetch kills for all systems
    tasks =
      system_ids
      |> Enum.map(fn system_id ->
        Task.async(fn ->
          {system_id, fetch_system_kills(system_id, since_hours, limit)}
        end)
      end)

    # Collect results
    results =
      tasks
      |> Enum.map(&Task.await(&1, 30_000))
      |> Enum.reduce(%{}, fn {system_id, result}, acc ->
        case result do
          {:ok, kills} -> Map.put(acc, system_id, kills)
          {:error, _reason} -> Map.put(acc, system_id, [])
        end
      end)

    total_kills =
      case results do
        res when is_map(res) -> res |> Map.values() |> List.flatten() |> length()
        res when is_list(res) -> res |> List.flatten() |> length()
        _ -> 0
      end

    Logger.info("Fetched kills for multiple systems",
      requested_systems: length(system_ids),
      successful_systems: map_size(results),
      total_kills: total_kills
    )

    {:ok, results}
  end

  @impl true
  def fetch_cached_kills(system_id) do
    Logger.debug("Fetching cached kills", system_id: system_id)

    case Helper.get_system_killmails(system_id) do
      {:ok, kills} when is_list(kills) ->
        Logger.debug("Retrieved cached kills",
          system_id: system_id,
          kill_count: length(kills)
        )

        kills

      {:error, reason} ->
        Logger.warning("Failed to fetch cached kills",
          system_id: system_id,
          error: reason
        )

        []

      _ ->
        Logger.warning("Unexpected response from cache",
          system_id: system_id
        )

        []
    end
  end

  @impl true
  def fetch_cached_kills_for_systems(system_ids) do
    Logger.debug("Fetching cached kills for multiple systems",
      system_ids: system_ids
    )

    results =
      system_ids
      |> Enum.map(fn system_id ->
        {system_id, fetch_cached_kills(system_id)}
      end)
      |> Map.new()

    total_kills = results |> Map.values() |> List.flatten() |> length()

    Logger.debug("Retrieved cached kills for multiple systems",
      requested_systems: length(system_ids),
      total_cached_kills: total_kills
    )

    results
  end

  @impl true
  def subscribe_to_kills(subscriber_id, system_ids, callback_url \\ nil) do
    Logger.debug("Creating kill subscription",
      subscriber_id: subscriber_id,
      system_ids: system_ids,
      has_callback: !is_nil(callback_url)
    )

    case SubscriptionManager.subscribe(subscriber_id, system_ids, callback_url) do
      {:ok, subscription_id} ->
        Logger.info("Kill subscription created",
          subscriber_id: subscriber_id,
          subscription_id: subscription_id,
          system_count: length(system_ids)
        )

        {:ok, subscription_id}

      {:error, reason} ->
        Logger.error("Failed to create kill subscription",
          subscriber_id: subscriber_id,
          error: reason
        )

        {:error, reason}
    end
  end

  @impl true
  def unsubscribe_from_kills(subscriber_id) do
    Logger.debug("Removing kill subscription", subscriber_id: subscriber_id)

    case SubscriptionManager.unsubscribe(subscriber_id) do
      :ok ->
        Logger.info("Kill subscription removed", subscriber_id: subscriber_id)
        :ok

      {:error, reason} ->
        Logger.error("Failed to remove kill subscription",
          subscriber_id: subscriber_id,
          error: reason
        )

        {:error, reason}
    end
  end

  @impl true
  def get_killmail(killmail_id) do
    Logger.debug("Fetching specific killmail", killmail_id: killmail_id)

    case ZkbClient.fetch_killmail(killmail_id) do
      {:ok, killmail} ->
        Logger.debug("Successfully fetched killmail", killmail_id: killmail_id)
        {:ok, killmail}

      {:error, reason} ->
        Logger.warning("Failed to fetch killmail",
          killmail_id: killmail_id,
          error: reason
        )

        {:error, reason}
    end
  end

  @impl true
  def get_system_kill_count(system_id) do
    Logger.debug("Fetching system kill count", system_id: system_id)

    case Helper.get_system_killmails(system_id) do
      {:ok, killmail_ids} when is_list(killmail_ids) ->
        count = length(killmail_ids)
        Logger.debug("Retrieved system kill count",
          system_id: system_id,
          count: count
        )

        count
      _ ->
        0
    end
  end

  # Private helper functions

  defp filter_kills_by_time(kills, since_hours) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-since_hours * 3600, :second)

    Enum.filter(kills, fn kill ->
      case get_kill_time(kill) do
        {:ok, kill_time} -> DateTime.compare(kill_time, cutoff_time) != :lt
        {:error, _} -> false
      end
    end)
  end

  defp get_kill_time(kill) do
    case extract_time_from_killmail(kill) do
      {:ok, time} -> {:ok, time}
      {:continue, kill} ->
        case extract_time_from_kill_time(kill) do
          {:ok, time} -> {:ok, time}
          {:continue, kill} -> extract_time_from_zkb(kill)
        end
    end
  end

  defp extract_time_from_killmail(kill) do
    if is_map(kill) and Map.has_key?(kill, "killmail_time") do
      case parse_datetime(kill["killmail_time"]) do
        {:ok, datetime} -> {:ok, datetime}
        {:error, _} -> {:continue, kill}
      end
    else
      {:continue, kill}
    end
  end

  defp extract_time_from_kill_time(kill) do
    if is_map(kill) and Map.has_key?(kill, "kill_time") do
      case parse_datetime(kill["kill_time"]) do
        {:ok, datetime} -> {:ok, datetime}
        {:error, _} -> {:continue, kill}
      end
    else
      {:continue, kill}
    end
  end

  defp extract_time_from_zkb({:continue, kill}) do
    if is_map(kill) and Map.has_key?(kill, "zkb") do
      extract_time_from_zkb_metadata(kill["zkb"])
    else
      {:error, :no_time_found}
    end
  end

  defp extract_time_from_zkb_metadata(zkb) when is_map(zkb) do
    if Map.has_key?(zkb, "killmail_time") do
      parse_datetime(zkb["killmail_time"])
    else
      {:error, :no_time_in_zkb}
    end
  end

  defp extract_time_from_zkb_metadata(_), do: {:error, :invalid_zkb_data}

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_datetime(%DateTime{} = datetime), do: {:ok, datetime}
  defp parse_datetime(_), do: {:error, :invalid_datetime_format}

  @doc """
  Convenience function to broadcast kill updates to subscribers.
  This would typically be called by background processes when new kills are detected.
  """
  @spec broadcast_kill_update(integer(), [map()]) :: :ok
  def broadcast_kill_update(system_id, kills) do
    SubscriptionManager.broadcast_kill_update(system_id, kills)
  end

  @doc """
  Convenience function to broadcast kill count updates to subscribers.
  This would typically be called by background processes when kill counts change.
  """
  @spec broadcast_kill_count_update(integer(), integer()) :: :ok
  def broadcast_kill_count_update(system_id, count) do
    SubscriptionManager.broadcast_kill_count_update(system_id, count)
  end

  @doc """
  Lists all active subscriptions (for administrative purposes).
  """
  @spec list_subscriptions() :: [Types.subscription()]
  def list_subscriptions do
    SubscriptionManager.list_subscriptions()
  end
end
