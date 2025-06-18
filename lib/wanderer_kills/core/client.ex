defmodule WandererKills.Core.Client do
  @moduledoc """
  Main client implementation for WandererKills service.

  This module implements the WandererKills.ClientBehaviour and provides
  a unified interface for fetching killmails, managing subscriptions,
  and accessing cached data. It coordinates between the ZKB client,
  cache, and subscription manager.
  """

  @behaviour WandererKills.Core.ClientBehaviour

  require Logger

  alias WandererKills.Core.Cache
  alias WandererKills.Core.Support.Error
  alias WandererKills.Core.Types
  alias WandererKills.Ingest.Killmails.ZkbClient
  alias WandererKills.Subs.SubscriptionManager

  @impl true
  def fetch_system_killmails(system_id, since_hours, limit) do
    Logger.debug("Fetching system killmails via WandererKills.Client",
      system_id: system_id,
      since_hours: since_hours,
      limit: limit
    )

    # Convert limit and since_hours to options for the new API
    past_seconds = since_hours * 3600
    opts = [past_seconds: past_seconds]

    case ZkbClient.fetch_system_killmails(system_id, opts) do
      {:ok, killmails} ->
        # Filter by time window if needed (since ZKB API doesn't support time filtering directly)
        filtered_killmails = filter_killmails_by_time(killmails, since_hours)
        limited_killmails = Enum.take(filtered_killmails, limit)

        Logger.debug("Successfully fetched system killmails",
          system_id: system_id,
          total_killmails: length(killmails),
          filtered_killmails: length(filtered_killmails),
          returned_killmails: length(limited_killmails)
        )

        {:ok, limited_killmails}

      {:error, reason} ->
        Logger.error("Failed to fetch system killmails",
          system_id: system_id,
          since_hours: since_hours,
          limit: limit,
          error: reason
        )

        {:error, reason}
    end
  end

  @impl true
  def fetch_systems_killmails(system_ids, since_hours, limit) do
    Logger.debug("Fetching killmails for multiple systems",
      system_ids: system_ids,
      since_hours: since_hours,
      limit: limit
    )

    # Batch fetch killmails for all systems using supervised tasks
    tasks =
      system_ids
      |> Enum.map(fn system_id ->
        Task.Supervisor.async(WandererKills.TaskSupervisor, fn ->
          {system_id, fetch_system_killmails(system_id, since_hours, limit)}
        end)
      end)

    # Collect results
    results =
      tasks
      |> Enum.map(&Task.await(&1, 30_000))
      |> Enum.reduce(%{}, fn {system_id, result}, acc ->
        case result do
          {:ok, killmails} -> Map.put(acc, system_id, killmails)
          {:error, _reason} -> Map.put(acc, system_id, [])
        end
      end)

    total_killmails =
      case results do
        res when is_map(res) -> res |> Map.values() |> List.flatten() |> length()
        res when is_list(res) -> res |> List.flatten() |> length()
        _ -> 0
      end

    Logger.debug("Fetched killmails for multiple systems",
      requested_systems: length(system_ids),
      successful_systems: map_size(results),
      total_killmails: total_killmails
    )

    {:ok, results}
  end

  @impl true
  def fetch_cached_killmails(system_id) do
    Logger.debug("Fetching cached killmails", system_id: system_id)

    case Cache.list_system_killmails(system_id) do
      {:ok, killmails} when is_list(killmails) ->
        Logger.debug("Retrieved cached killmails",
          system_id: system_id,
          killmail_count: length(killmails)
        )

        killmails

      {:error, reason} ->
        Logger.warning("Failed to fetch cached killmails",
          system_id: system_id,
          error: reason
        )

        []
    end
  end

  @impl true
  def fetch_cached_killmails_for_systems(system_ids) do
    Logger.debug("Fetching cached killmails for multiple systems",
      system_ids: system_ids
    )

    results =
      system_ids
      |> Enum.map(fn system_id ->
        {system_id, fetch_cached_killmails(system_id)}
      end)
      |> Map.new()

    total_killmails = results |> Map.values() |> List.flatten() |> length()

    Logger.debug("Retrieved cached killmails for multiple systems",
      requested_systems: length(system_ids),
      total_cached_killmails: total_killmails
    )

    results
  end

  @impl true
  def subscribe_to_killmails(subscriber_id, system_ids, callback_url \\ nil) do
    Logger.debug("Creating killmail subscription",
      subscriber_id: subscriber_id,
      system_ids: system_ids,
      has_callback: !is_nil(callback_url)
    )

    case SubscriptionManager.subscribe(subscriber_id, system_ids, callback_url) do
      {:ok, subscription_id} ->
        Logger.debug("Killmail subscription created",
          subscriber_id: subscriber_id,
          subscription_id: subscription_id,
          system_count: length(system_ids)
        )

        {:ok, subscription_id}

      {:error, reason} ->
        Logger.error("Failed to create killmail subscription",
          subscriber_id: subscriber_id,
          error: reason
        )

        {:error, reason}
    end
  end

  @impl true
  def unsubscribe_from_killmails(subscriber_id) do
    Logger.debug("Removing killmail subscription", subscriber_id: subscriber_id)

    case SubscriptionManager.unsubscribe(subscriber_id) do
      :ok ->
        Logger.debug("Killmail subscription removed", subscriber_id: subscriber_id)
        :ok

      {:error, reason} ->
        Logger.error("Failed to remove killmail subscription",
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
        killmail

      {:error, reason} ->
        Logger.warning("Failed to fetch killmail",
          killmail_id: killmail_id,
          error: reason
        )

        nil
    end
  end

  @impl true
  def get_system_killmail_count(system_id) do
    Logger.debug("Fetching system killmail count", system_id: system_id)

    case Cache.list_system_killmails(system_id) do
      {:ok, killmail_ids} when is_list(killmail_ids) ->
        count = length(killmail_ids)

        Logger.debug("Retrieved system killmail count",
          system_id: system_id,
          count: count
        )

        count

      _ ->
        0
    end
  end

  # Private helper functions

  defp filter_killmails_by_time(killmails, since_hours) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-since_hours * 3600, :second)

    Enum.filter(killmails, fn killmail ->
      case get_killmail_time(killmail) do
        {:ok, killmail_time} -> DateTime.compare(killmail_time, cutoff_time) != :lt
        {:error, _} -> false
      end
    end)
  end

  defp get_killmail_time(killmail) do
    case extract_time_from_killmail(killmail) do
      {:ok, time} ->
        {:ok, time}

      {:continue, killmail} ->
        case extract_time_from_killmail_time(killmail) do
          {:ok, time} -> {:ok, time}
          {:continue, killmail} -> extract_time_from_zkb(killmail)
        end
    end
  end

  defp extract_time_from_killmail(killmail) do
    if is_map(killmail) and Map.has_key?(killmail, "killmail_time") do
      case parse_datetime(killmail["killmail_time"]) do
        {:ok, datetime} -> {:ok, datetime}
        {:error, _} -> {:continue, killmail}
      end
    else
      {:continue, killmail}
    end
  end

  defp extract_time_from_killmail_time(killmail) do
    if is_map(killmail) and Map.has_key?(killmail, "kill_time") do
      case parse_datetime(killmail["kill_time"]) do
        {:ok, datetime} -> {:ok, datetime}
        {:error, _} -> {:continue, killmail}
      end
    else
      {:continue, killmail}
    end
  end

  defp extract_time_from_zkb({:continue, killmail}) do
    if is_map(killmail) and Map.has_key?(killmail, "zkb") do
      extract_time_from_zkb_metadata(killmail["zkb"])
    else
      {:error, Error.time_error(:no_time_found, "No time field found in killmail")}
    end
  end

  defp extract_time_from_zkb_metadata(zkb) when is_map(zkb) do
    if Map.has_key?(zkb, "killmail_time") do
      parse_datetime(zkb["killmail_time"])
    else
      {:error, Error.time_error(:no_time_in_zkb, "No time field in zkb metadata")}
    end
  end

  defp extract_time_from_zkb_metadata(_),
    do: {:error, Error.validation_error(:invalid_zkb_data, "Invalid zkb metadata format")}

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_datetime(%DateTime{} = datetime), do: {:ok, datetime}
  defp parse_datetime(_), do: {:error, :invalid_datetime_format}

  @doc """
  Convenience function to broadcast killmail updates to subscribers.
  This would typically be called by background processes when new killmails are detected.
  """
  @spec broadcast_killmail_update(integer(), [map()]) :: :ok
  def broadcast_killmail_update(system_id, killmails) do
    SubscriptionManager.broadcast_killmail_update_async(system_id, killmails)
  end

  @doc """
  Convenience function to broadcast killmail count updates to subscribers.
  This would typically be called by background processes when killmail counts change.
  """
  @spec broadcast_killmail_count_update(integer(), integer()) :: :ok
  def broadcast_killmail_count_update(system_id, count) do
    SubscriptionManager.broadcast_killmail_count_update_async(system_id, count)
  end

  @doc """
  Lists all active subscriptions (for administrative purposes).
  """
  @spec list_subscriptions() :: [Types.subscription()]
  def list_subscriptions do
    SubscriptionManager.list_subscriptions()
  end
end
