defmodule WandererKills.Subscriptions.Broadcaster do
  @moduledoc """
  Handles PubSub broadcasting for killmail subscriptions.

  This module centralizes all broadcasting logic for killmail updates,
  ensuring consistent message formatting and topic management.
  """

  require Logger
  alias WandererKills.Support.PubSubTopics

  @pubsub_name WandererKills.PubSub

  @doc """
  Broadcasts a killmail update to all relevant PubSub topics.

  ## Parameters
  - `system_id` - The system ID for the kills
  - `kills` - List of killmail data

  ## Topics broadcasted to:
  - System-specific topic for the given system_id
  - All systems topic
  - WebSocket statistics topic
  """
  @spec broadcast_killmail_update(integer(), list(map())) :: :ok
  def broadcast_killmail_update(system_id, kills) do
    message = %{
      type: :killmail_update,
      system_id: system_id,
      kills: kills,
      timestamp: DateTime.utc_now()
    }

    # Broadcast to system-specific topic
    system_topic = PubSubTopics.system_topic(system_id)
    :ok = Phoenix.PubSub.broadcast(@pubsub_name, system_topic, message)

    # Broadcast to detailed system topic as well
    detailed_topic = PubSubTopics.system_detailed_topic(system_id)
    :ok = Phoenix.PubSub.broadcast(@pubsub_name, detailed_topic, message)

    # Broadcast to all systems topic
    all_systems_topic = PubSubTopics.all_systems_topic()
    :ok = Phoenix.PubSub.broadcast(@pubsub_name, all_systems_topic, message)

    log_broadcast(system_id, kills)
    :ok
  end

  @doc """
  Broadcasts a killmail count update to all relevant PubSub topics.

  ## Parameters
  - `system_id` - The system ID for the count
  - `count` - Number of killmails
  """
  @spec broadcast_killmail_count(integer(), integer()) :: :ok
  def broadcast_killmail_count(system_id, count) do
    message = %{
      type: :killmail_count_update,
      system_id: system_id,
      count: count,
      timestamp: DateTime.utc_now()
    }

    # Broadcast to system-specific topic
    system_topic = PubSubTopics.system_topic(system_id)
    :ok = Phoenix.PubSub.broadcast(@pubsub_name, system_topic, message)

    # Broadcast to detailed system topic as well
    detailed_topic = PubSubTopics.system_detailed_topic(system_id)
    :ok = Phoenix.PubSub.broadcast(@pubsub_name, detailed_topic, message)

    Logger.debug("Broadcasted killmail count update system_id=#{system_id} count=#{count}")

    :ok
  end

  @doc """
  Gets the PubSub name used for broadcasting.
  """
  @spec pubsub_name() :: atom()
  def pubsub_name, do: @pubsub_name

  # Private Functions

  defp log_broadcast(system_id, kills) do
    case kills do
      [] ->
        Logger.debug("Broadcasted empty killmail update system_id=#{system_id}")

      kills ->
        Logger.debug("Broadcasted killmail update system_id=#{system_id} kill_count=#{length(kills)}")
    end
  end
end
