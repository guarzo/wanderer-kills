defmodule WandererKills.SubscriptionManager do
  @moduledoc """
  GenServer that manages kill subscriptions and notifications.

  This module handles:
  - Tracking active subscriptions
  - Managing subscriber notifications via webhooks and PubSub
  - Broadcasting kill updates to subscribers
  """

  use GenServer
  require Logger
  alias WandererKills.Types

  @type subscription_id :: String.t()
  @type subscriber_id :: String.t()
  @type system_id :: integer()

  # Client API

  @doc """
  Starts the subscription manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Subscribes to kill updates for specified systems.
  """
  @spec subscribe(subscriber_id(), [system_id()], String.t() | nil) ::
          {:ok, subscription_id()} | {:error, term()}
  def subscribe(subscriber_id, system_ids, callback_url \\ nil) do
    GenServer.call(__MODULE__, {:subscribe, subscriber_id, system_ids, callback_url})
  end

  @doc """
  Unsubscribes from all kill updates for a subscriber.
  """
  @spec unsubscribe(subscriber_id()) :: :ok | {:error, term()}
  def unsubscribe(subscriber_id) do
    GenServer.call(__MODULE__, {:unsubscribe, subscriber_id})
  end

  @doc """
  Lists all active subscriptions.
  """
  @spec list_subscriptions() :: [Types.subscription()]
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end

  @doc """
  Broadcasts a kill update to all relevant subscribers.
  """
  @spec broadcast_kill_update(system_id(), [Types.kill()]) :: :ok
  def broadcast_kill_update(system_id, kills) do
    GenServer.cast(__MODULE__, {:broadcast_kill_update, system_id, kills})
  end

  @doc """
  Broadcasts a kill count update to all relevant subscribers.
  """
  @spec broadcast_kill_count_update(system_id(), integer()) :: :ok
  def broadcast_kill_count_update(system_id, count) do
    GenServer.cast(__MODULE__, {:broadcast_kill_count_update, system_id, count})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    pubsub_name = Keyword.get(opts, :pubsub_name, WandererKills.PubSub)

    state = %{
      subscriptions: %{},
      pubsub_name: pubsub_name
    }

    Logger.info("SubscriptionManager started", pubsub_name: pubsub_name)
    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, subscriber_id, system_ids, callback_url}, _from, state) do
    case validate_subscription_params(subscriber_id, system_ids, callback_url) do
      :ok ->
        subscription_id = generate_subscription_id(subscriber_id)

        subscription = %{
          subscriber_id: subscriber_id,
          system_ids: system_ids,
          callback_url: callback_url,
          created_at: DateTime.utc_now()
        }

        new_subscriptions = Map.put(state.subscriptions, subscription_id, subscription)
        new_state = %{state | subscriptions: new_subscriptions}

        Logger.info("Subscription created",
          subscriber_id: subscriber_id,
          subscription_id: subscription_id,
          system_ids: system_ids,
          has_callback: !is_nil(callback_url)
        )

        # Preload and send recent kills for the subscribed systems
        Task.start(fn ->
          preload_kills_for_new_subscriber(subscription, system_ids)
        end)

        {:reply, {:ok, subscription_id}, new_state}

      {:error, reason} ->
        Logger.warning("Subscription creation failed",
          subscriber_id: subscriber_id,
          reason: reason
        )

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe, subscriber_id}, _from, state) do
    {removed_subscriptions, remaining_subscriptions} =
      Enum.split_with(state.subscriptions, fn {_id, sub} ->
        sub.subscriber_id == subscriber_id
      end)

    if Enum.empty?(removed_subscriptions) do
      Logger.warning("Unsubscribe failed: subscriber not found", subscriber_id: subscriber_id)
      {:reply, {:error, :not_found}, state}
    else
      new_state = %{state | subscriptions: Map.new(remaining_subscriptions)}
      removed_count = length(removed_subscriptions)

      Logger.info("Subscription removed",
        subscriber_id: subscriber_id,
        removed_count: removed_count
      )

      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_subscriptions, _from, state) do
    subscriptions =
      state.subscriptions
      |> Enum.map(fn {_id, subscription} -> subscription end)

    {:reply, subscriptions, state}
  end

  @impl true
  def handle_cast({:broadcast_kill_update, system_id, kills}, state) do
    # Find all subscribers interested in this system
    interested_subscriptions =
      state.subscriptions
      |> Enum.filter(fn {_id, sub} -> system_id in sub.system_ids end)

    if not Enum.empty?(interested_subscriptions) do
      # Broadcast via PubSub
      broadcast_pubsub_update(state.pubsub_name, system_id, kills, :detailed_kill_update)

      # Send webhook notifications
      Task.start(fn ->
        send_webhook_notifications(interested_subscriptions, system_id, kills, :kill_update)
      end)

      Logger.debug("Kill update broadcasted",
        system_id: system_id,
        kill_count: length(kills),
        subscriber_count: length(interested_subscriptions)
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:broadcast_kill_count_update, system_id, count}, state) do
    # Find all subscribers interested in this system
    interested_subscriptions =
      state.subscriptions
      |> Enum.filter(fn {_id, sub} -> system_id in sub.system_ids end)

    if not Enum.empty?(interested_subscriptions) do
      # Broadcast via PubSub
      broadcast_pubsub_count_update(state.pubsub_name, system_id, count)

      # Send webhook notifications
      Task.start(fn ->
        send_webhook_count_notifications(interested_subscriptions, system_id, count)
      end)

      Logger.debug("Kill count update broadcasted",
        system_id: system_id,
        count: count,
        subscriber_count: length(interested_subscriptions)
      )
    end

    {:noreply, state}
  end

  # Private helper functions

  defp validate_subscription_params(subscriber_id, system_ids, callback_url) do
    cond do
      not is_binary(subscriber_id) or String.trim(subscriber_id) == "" ->
        {:error, :invalid_subscriber_id}

      not is_list(system_ids) or Enum.empty?(system_ids) ->
        {:error, :invalid_system_ids}

      not Enum.all?(system_ids, &is_integer/1) ->
        {:error, :invalid_system_ids}

      not is_nil(callback_url) and not is_binary(callback_url) ->
        {:error, :invalid_callback_url}

      true ->
        :ok
    end
  end

  defp generate_subscription_id(subscriber_id) do
    timestamp = System.system_time(:microsecond)

    :crypto.hash(:sha256, "#{subscriber_id}-#{timestamp}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  defp broadcast_pubsub_update(pubsub_name, system_id, kills, type) do
    timestamp = DateTime.utc_now()

    # Global kill updates
    Phoenix.PubSub.broadcast(pubsub_name, "zkb:detailed_kills:updated", %{
      type: type,
      solar_system_id: system_id,
      kills: kills,
      timestamp: timestamp
    })

    # System-specific updates
    Phoenix.PubSub.broadcast(pubsub_name, "zkb:system:#{system_id}", %{
      type: type,
      solar_system_id: system_id,
      kills: kills,
      timestamp: timestamp
    })

    Phoenix.PubSub.broadcast(pubsub_name, "zkb:system:#{system_id}:detailed", %{
      type: type,
      solar_system_id: system_id,
      kills: kills,
      timestamp: timestamp
    })
  end

  defp broadcast_pubsub_count_update(pubsub_name, system_id, count) do
    timestamp = DateTime.utc_now()

    # Global kill count updates
    Phoenix.PubSub.broadcast(pubsub_name, "zkb:kills:updated", %{
      type: :kill_count_update,
      solar_system_id: system_id,
      kills: count,
      timestamp: timestamp
    })

    # System-specific updates
    Phoenix.PubSub.broadcast(pubsub_name, "zkb:system:#{system_id}", %{
      type: :kill_count_update,
      solar_system_id: system_id,
      kills: count,
      timestamp: timestamp
    })
  end

  defp send_webhook_notifications(subscriptions, system_id, kills, type) do
    subscriptions
    |> Enum.filter(fn {_id, sub} -> not is_nil(sub.callback_url) end)
    |> Enum.each(fn {_id, sub} ->
      send_webhook_notification(sub, system_id, kills, type)
    end)
  end

  defp send_webhook_count_notifications(subscriptions, system_id, count) do
    subscriptions
    |> Enum.filter(fn {_id, sub} -> not is_nil(sub.callback_url) end)
    |> Enum.each(fn {_id, sub} ->
      send_webhook_count_notification(sub, system_id, count)
    end)
  end

  defp send_webhook_notification(subscription, system_id, kills, type) do
    payload = %{
      type: type,
      data: %{
        solar_system_id: system_id,
        kills: kills,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    case Req.post(subscription.callback_url,
           json: payload,
           headers: [{"Content-Type", "application/json"}],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        Logger.debug("Webhook notification sent successfully",
          subscriber_id: subscription.subscriber_id,
          callback_url: subscription.callback_url,
          status: status
        )

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Webhook notification failed",
          subscriber_id: subscription.subscriber_id,
          callback_url: subscription.callback_url,
          status: status
        )

      {:error, reason} ->
        Logger.error("Webhook notification error",
          subscriber_id: subscription.subscriber_id,
          callback_url: subscription.callback_url,
          error: inspect(reason)
        )
    end
  end

  defp send_webhook_count_notification(subscription, system_id, count) do
    payload = %{
      type: "kill_count_update",
      data: %{
        solar_system_id: system_id,
        count: count,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    case Req.post(subscription.callback_url,
           json: payload,
           headers: [{"Content-Type", "application/json"}],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        Logger.debug("Webhook count notification sent successfully",
          subscriber_id: subscription.subscriber_id,
          callback_url: subscription.callback_url,
          status: status
        )

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Webhook count notification failed",
          subscriber_id: subscription.subscriber_id,
          callback_url: subscription.callback_url,
          status: status
        )

      {:error, reason} ->
        Logger.error("Webhook count notification error",
          subscriber_id: subscription.subscriber_id,
          callback_url: subscription.callback_url,
          error: inspect(reason)
        )
    end
  end

  # Preload and send recent kills for a new subscriber
  defp preload_kills_for_new_subscriber(subscription, system_ids) do
    Logger.info("Preloading kills for new subscriber",
      subscriber_id: subscription.subscriber_id,
      system_count: length(system_ids)
    )

    # Fetch recent kills for each system (limit to 24 hours and 10 kills per system)
    limit_per_system = 10
    since_hours = 24

    total_kills_sent =
      system_ids
      |> Enum.map(fn system_id ->
        preload_system_kills(subscription, system_id, since_hours, limit_per_system)
      end)
      |> Enum.sum()

    Logger.info("Preload completed for new subscriber",
      subscriber_id: subscription.subscriber_id,
      total_systems: length(system_ids),
      total_kills_sent: total_kills_sent
    )
  end

  # Preload kills for a specific system and send to subscriber
  defp preload_system_kills(subscription, system_id, since_hours, limit) do
    Logger.debug("Preloading kills for system",
      subscriber_id: subscription.subscriber_id,
      system_id: system_id,
      since_hours: since_hours,
      limit: limit
    )

    # Try cached enriched kills first
    kills =
      case get_cached_enriched_kills(system_id, limit) do
        enriched_kills when enriched_kills != [] ->
          Logger.debug("Using cached enriched kills for preload",
            system_id: system_id,
            cached_count: length(enriched_kills)
          )

          enriched_kills

        [] ->
          # Fetch and enrich fresh kills from ZKB (ensure minimum 5 kills for useful preload)
          min_preload_limit = max(limit, 5)

          Logger.debug("Fetching and enriching fresh kills for preload",
            system_id: system_id,
            target_limit: min_preload_limit
          )

          fetch_and_enrich_kills(system_id, min_preload_limit, since_hours)
      end

    # Send kills to subscriber if we have any
    if length(kills) > 0 do
      # Send via PubSub
      broadcast_pubsub_update(WandererKills.PubSub, system_id, kills, :preload_kill_update)

      # Send via webhook if configured
      if subscription.callback_url do
        send_webhook_notification(subscription, system_id, kills, :preload_kill_update)
      end

      Logger.debug("Sent preloaded kills to subscriber",
        subscriber_id: subscription.subscriber_id,
        system_id: system_id,
        kill_count: length(kills)
      )

      length(kills)
    else
      Logger.debug("No kills to preload for system",
        subscriber_id: subscription.subscriber_id,
        system_id: system_id
      )

      0
    end
  end

  # Helper function to get cached enriched killmails for a system
  defp get_cached_enriched_kills(system_id, limit) do
    case WandererKills.Cache.Helper.system_get_killmails(system_id) do
      {:ok, killmail_ids} when is_list(killmail_ids) ->
        fetch_enriched_killmails(killmail_ids, limit)

      {:error, _reason} ->
        []
    end
  end

  # Helper function to fetch enriched killmails from cache
  defp fetch_enriched_killmails(killmail_ids, limit) do
    killmail_ids
    |> Enum.take(limit)
    |> Enum.map(&get_single_enriched_killmail/1)
    |> Enum.filter(&(&1 != nil))
  end

  # Helper function to fetch a single enriched killmail from cache
  defp get_single_enriched_killmail(killmail_id) do
    case WandererKills.Cache.Helper.killmail_get(killmail_id) do
      {:ok, enriched_killmail} -> enriched_killmail
      {:error, _reason} -> nil
    end
  end

  # Helper function to fetch and enrich kills from ZKB
  defp fetch_and_enrich_kills(system_id, limit, since_hours) do
    Logger.debug("No cached kills available, fetching fresh kills for preload",
      system_id: system_id,
      limit: limit,
      since_hours: since_hours
    )

    try do
      # Fetch recent kills from ZKB API
      case fetch_zkb_kills_for_system(system_id, limit, since_hours) do
        {:ok, zkb_kills} when is_list(zkb_kills) and length(zkb_kills) > 0 ->
          Logger.info("Fetched recent kills from ZKB for preload",
            system_id: system_id,
            kill_count: length(zkb_kills)
          )

          # Parse and enrich the kills
          enrich_zkb_kills_for_preload(zkb_kills)

        {:ok, []} ->
          Logger.debug("No recent kills found in ZKB for system", system_id: system_id)
          []

        {:error, reason} ->
          Logger.warning("Failed to fetch kills from ZKB for preload",
            system_id: system_id,
            error: inspect(reason)
          )

          []
      end
    rescue
      error ->
        Logger.error("Error during preload kill fetch",
          system_id: system_id,
          error: inspect(error)
        )

        []
    end
  end

  # Fetch recent kills from ZKB API for a specific system
  defp fetch_zkb_kills_for_system(system_id, limit, since_hours) do
    # Calculate the time cutoff
    cutoff_time = DateTime.utc_now() |> DateTime.add(-since_hours * 3600, :second)

    # Build ZKB API URL for system kills
    zkb_url = "https://zkillboard.com/api/systemID/#{system_id}/"

    case Req.get(zkb_url,
           headers: [{"User-Agent", "wanderer-kills/1.0"}],
           receive_timeout: 30_000
         ) do
      {:ok, %Req.Response{status: 200, body: kills}} when is_list(kills) ->
        recent_kills = filter_recent_kills(kills, cutoff_time, limit)
        {:ok, recent_kills}

      {:ok, %Req.Response{status: status}} ->
        {:error, "ZKB API returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Filter recent kills and take only the requested limit
  defp filter_recent_kills(kills, cutoff_time, limit) do
    kills
    |> Enum.filter(&is_kill_recent?(&1, cutoff_time))
    |> Enum.take(limit)
  end

  # Check if a kill is recent enough for preload
  defp is_kill_recent?(kill, cutoff_time) do
    case WandererKills.Infrastructure.Clock.get_killmail_time(kill) do
      {:ok, kill_time} -> DateTime.compare(kill_time, cutoff_time) != :lt
      {:error, _} -> false
    end
  end

  # Enrich ZKB kills for preload (with error handling)
  defp enrich_zkb_kills_for_preload(zkb_kills) do
    zkb_kills
    |> Enum.map(&enrich_single_zkb_kill_for_preload/1)
    |> Enum.filter(&(&1 != nil))
  end

  # Enrich a single ZKB kill for preload with graceful error handling
  defp enrich_single_zkb_kill_for_preload(zkb_kill) do
    try do
      # Extract killmail data and zkb metadata correctly
      killmail_data = Map.drop(zkb_kill, ["zkb"])
      zkb_data = Map.get(zkb_kill, "zkb", %{})

      # Use a reasonable cutoff (24 hours ago) for preload
      cutoff = DateTime.utc_now() |> DateTime.add(-24 * 3600, :second)

      # Parse and enrich the kill with correct parameters
      case WandererKills.Killmails.Coordinator.parse_full_and_store(
             killmail_data,
             %{"zkb" => zkb_data},
             cutoff
           ) do
        {:ok, enriched_killmail} when is_map(enriched_killmail) ->
          # Return the enriched killmail directly
          enriched_killmail

        {:ok, _} ->
          # If parse_full_and_store returned something else, try to fetch from cache
          case WandererKills.Cache.Helper.killmail_get(Map.get(zkb_kill, "killmail_id")) do
            {:ok, enriched_killmail} -> enriched_killmail
            {:error, _} -> nil
          end

        {:error, reason} ->
          Logger.debug("Failed to enrich kill for preload",
            killmail_id: Map.get(zkb_kill, "killmail_id"),
            reason: inspect(reason)
          )

          nil
      end
    rescue
      error ->
        Logger.debug("Error enriching kill for preload",
          killmail_id: Map.get(zkb_kill, "killmail_id"),
          error: inspect(error)
        )

        nil
    end
  end
end
