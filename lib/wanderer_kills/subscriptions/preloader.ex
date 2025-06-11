defmodule WandererKills.Subscriptions.Preloader do
  @moduledoc """
  Handles preloading of killmail data for new subscriptions.

  This module manages the asynchronous preloading of recent killmails
  when a new subscription is created, ensuring subscribers receive
  historical data.
  """

  require Logger
  alias WandererKills.Preloader
  alias WandererKills.Subscriptions.{Broadcaster, WebhookNotifier}

  # Preload configuration
  @default_limit_per_system 5
  @default_since_hours 24

  @doc """
  Preloads recent kills for a new subscriber's systems.

  This function spawns an asynchronous task to:
  1. Fetch recent kills for each subscribed system
  2. Broadcast updates via PubSub
  3. Send webhook notifications if configured

  ## Parameters
  - `subscription` - The subscription map containing system_ids and callback_url
  - `opts` - Options for preloading:
    - `:limit_per_system` - Max kills per system (default: 5)
    - `:since_hours` - Hours to look back (default: 24)

  ## Returns
  - `:ok` immediately (processing happens asynchronously)
  """
  @spec preload_for_subscription(map(), keyword()) :: :ok
  def preload_for_subscription(subscription, opts \\ []) do
    limit_per_system = Keyword.get(opts, :limit_per_system, @default_limit_per_system)
    since_hours = Keyword.get(opts, :since_hours, @default_since_hours)

    # Start supervised async task
    alias WandererKills.Support.SupervisedTask
    
    SupervisedTask.start_child(
      fn -> do_preload(subscription, limit_per_system, since_hours) end,
      task_name: "subscription_preload",
      metadata: %{
        subscription_id: subscription["id"],
        system_count: length(subscription["system_ids"])
      }
    )

    :ok
  end

  # Private Functions

  defp do_preload(subscription, limit_per_system, since_hours) do
    %{
      "id" => subscription_id,
      "subscriber_id" => subscriber_id,
      "system_ids" => system_ids,
      "callback_url" => callback_url
    } = subscription

    Logger.info("🔄 Starting kill preload for new subscription",
      subscription_id: subscription_id,
      subscriber_id: subscriber_id,
      system_count: length(system_ids),
      limit_per_system: limit_per_system,
      since_hours: since_hours
    )

    # Process each system
    results = 
      system_ids
      |> Enum.map(&preload_system(&1, limit_per_system, since_hours))
      |> Enum.filter(fn {_system_id, kills} -> length(kills) > 0 end)

    # Broadcast and notify for each system with kills
    Enum.each(results, fn {system_id, kills} ->
      # Always broadcast to PubSub
      Broadcaster.broadcast_killmail_update(system_id, kills)

      # Send webhook if configured
      if callback_url do
        WebhookNotifier.notify_webhook(callback_url, system_id, kills, subscription_id)
      end
    end)

    total_kills = results |> Enum.map(fn {_, kills} -> length(kills) end) |> Enum.sum()

    Logger.info("✅ Completed kill preload",
      subscription_id: subscription_id,
      systems_with_kills: length(results),
      total_kills: total_kills
    )
  rescue
    error ->
      Logger.error("❌ Failed to preload kills for subscription",
        subscription_id: subscription["id"],
        error: inspect(error)
      )
  end

  defp preload_system(system_id, limit, since_hours) do
    kills = Preloader.preload_kills_for_system(system_id, limit, since_hours)
    
    if length(kills) > 0 do
      Logger.debug("📦 Preloaded kills for system",
        system_id: system_id,
        kill_count: length(kills)
      )
    end

    {system_id, kills}
  end
end