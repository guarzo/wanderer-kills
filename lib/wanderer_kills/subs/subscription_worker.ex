defmodule WandererKills.Subs.SubscriptionWorker do
  @moduledoc """
  GenServer that manages an individual subscription.

  Each subscription is its own process, providing crash isolation.
  When a subscription worker crashes, it doesn't affect other subscriptions.

  ## Features
  - Handles both webhook and WebSocket subscriptions
  - Automatic cleanup on termination
  - Process isolation for fault tolerance
  - Registry-based process lookup
  """

  use GenServer
  require Logger

  alias WandererKills.Subs.Subscriptions.{
    CharacterIndex,
    Filter,
    SystemIndex,
    WebhookNotifier
  }

  alias WandererKills.Core.Support.SupervisedTask
  alias WandererKills.Domain.Killmail

  @type subscription_id :: String.t()
  @type subscription :: map()

  defmodule State do
    @moduledoc false
    defstruct [
      :subscription_id,
      :subscription,
      :type,
      :socket_monitor_ref
    ]

    @type t :: %__MODULE__{
            subscription_id: String.t(),
            subscription: map(),
            type: :webhook | :websocket,
            socket_monitor_ref: reference() | nil
          }
  end

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a subscription worker for the given subscription.
  """
  @spec start_link(subscription()) :: GenServer.on_start()
  def start_link(%{"id" => subscription_id} = subscription) do
    GenServer.start_link(__MODULE__, subscription, name: via_tuple(subscription_id))
  end

  @doc """
  Updates the subscription configuration.
  """
  @spec update_subscription(subscription_id(), map()) :: :ok | {:error, term()}
  def update_subscription(subscription_id, updates) do
    case lookup_subscription(subscription_id) do
      :error -> {:error, :not_found}
      {:ok, pid} -> GenServer.call(pid, {:update_subscription, updates})
    end
  end

  @doc """
  Gets the current subscription state.
  """
  @spec get_subscription(subscription_id()) :: {:ok, subscription()} | {:error, :not_found}
  def get_subscription(subscription_id) do
    case lookup_subscription(subscription_id) do
      :error -> {:error, :not_found}
      {:ok, pid} -> GenServer.call(pid, :get_subscription)
    end
  end

  @doc """
  Handles a killmail update for this subscription.
  """
  @spec handle_killmail_update(subscription_id(), integer(), [Killmail.t()]) :: :ok
  def handle_killmail_update(subscription_id, system_id, kills) do
    case lookup_subscription(subscription_id) do
      # Subscription no longer exists, ignore
      :error -> :ok
      {:ok, pid} -> GenServer.cast(pid, {:killmail_update, system_id, kills})
    end
  end

  @doc """
  Looks up a subscription worker process.
  """
  @spec lookup_subscription(subscription_id()) :: {:ok, pid()} | :error
  def lookup_subscription(subscription_id) do
    case Registry.lookup(WandererKills.Subs.SubscriptionRegistry, subscription_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Gets the subscription ID for a process.
  """
  @spec get_subscription_id(pid()) :: {:ok, subscription_id()} | {:error, term()}
  def get_subscription_id(pid) do
    GenServer.call(pid, :get_subscription_id)
  catch
    :exit, _ -> {:error, :process_dead}
  end

  @doc """
  Gets the subscription type for a process.
  """
  @spec get_subscription_type(pid()) :: {:ok, :webhook | :websocket} | {:error, term()}
  def get_subscription_type(pid) do
    GenServer.call(pid, :get_subscription_type)
  catch
    :exit, _ -> {:error, :process_dead}
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(%{"id" => subscription_id} = subscription) do
    # Determine subscription type
    type = if Map.has_key?(subscription, "socket_pid"), do: :websocket, else: :webhook

    # Monitor WebSocket process if it's a WebSocket subscription
    socket_monitor_ref =
      if type == :websocket do
        socket_pid = subscription["socket_pid"]

        Logger.debug("Monitoring WebSocket process",
          subscription_id: subscription_id,
          socket_pid: inspect(socket_pid)
        )

        Process.monitor(socket_pid)
      end

    # Register subscription with indexes for efficient lookup
    register_with_indexes(subscription)

    state = %State{
      subscription_id: subscription_id,
      subscription: subscription,
      type: type,
      socket_monitor_ref: socket_monitor_ref
    }

    Logger.info("[INFO] Subscription worker started",
      subscription_id: subscription_id,
      type: type,
      subscriber_id: subscription["subscriber_id"],
      system_ids: subscription["system_ids"] || [],
      character_ids: subscription["character_ids"] || []
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:update_subscription, updates}, _from, state) do
    old_subscription = state.subscription
    new_subscription = Map.merge(old_subscription, updates)

    # Update indexes if system_ids or character_ids changed
    if systems_or_characters_changed?(old_subscription, new_subscription) do
      unregister_from_indexes(old_subscription)
      register_with_indexes(new_subscription)
    end

    new_state = %{state | subscription: new_subscription}

    Logger.debug("[DEBUG] Subscription updated",
      subscription_id: state.subscription_id,
      changes: updates
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_subscription, _from, state) do
    {:reply, {:ok, state.subscription}, state}
  end

  @impl true
  def handle_call(:get_subscription_id, _from, state) do
    {:reply, {:ok, state.subscription_id}, state}
  end

  @impl true
  def handle_call(:get_subscription_type, _from, state) do
    {:reply, {:ok, state.type}, state}
  end

  @impl true
  def handle_cast({:killmail_update, system_id, kills}, state) do
    Logger.info(
      "[INFO] SubscriptionWorker received killmail update - " <>
        "subscription_id: #{state.subscription_id}, system_id: #{system_id}, " <>
        "kills_received: #{length(kills)}, " <>
        "subscription_systems: #{inspect(state.subscription["system_ids"])}, " <>
        "subscription_characters: #{inspect(state.subscription["character_ids"])}"
    )

    # Filter kills that match this subscription
    matching_kills = Filter.filter_killmails(kills, state.subscription)

    Logger.info(
      "[INFO] SubscriptionWorker filtered killmails - " <>
        "subscription_id: #{state.subscription_id}, system_id: #{system_id}, " <>
        "original_count: #{length(kills)}, filtered_count: #{length(matching_kills)}, " <>
        "has_matches: #{length(matching_kills) > 0}"
    )

    if not Enum.empty?(matching_kills) do
      case state.type do
        :webhook ->
          send_webhook_notification(state, system_id, matching_kills)

        :websocket ->
          # Send directly to the WebSocket channel with the correct format
          send_to_websocket_channel(state, system_id, matching_kills)
      end

      Logger.info(
        "[INFO] Delivered killmails to subscription - " <>
          "subscription_id: #{state.subscription_id}, type: #{state.type}, " <>
          "system_id: #{system_id}, killmail_count: #{length(matching_kills)}"
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{socket_monitor_ref: ref} = state) do
    Logger.info("[INFO] WebSocket process terminated, stopping subscription worker",
      subscription_id: state.subscription_id,
      reason: inspect(reason)
    )

    # WebSocket disconnected, stop this worker
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("[WARNING] Subscription worker received unexpected message",
      subscription_id: state.subscription_id,
      message: inspect(msg)
    )

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[INFO] Subscription worker terminating",
      subscription_id: state.subscription_id,
      reason: inspect(reason)
    )

    # Clean up indexes
    unregister_from_indexes(state.subscription)

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp via_tuple(subscription_id) do
    {:via, Registry, {WandererKills.Subs.SubscriptionRegistry, subscription_id}}
  end

  defp register_with_indexes(subscription) do
    subscription_id = subscription["id"]

    # Register with system index
    if system_ids = subscription["system_ids"] do
      Logger.info(
        "[INFO] Registering subscription with SystemIndex - " <>
          "subscription_id: #{subscription_id}, systems: #{inspect(system_ids)}"
      )

      SystemIndex.add_subscription(subscription_id, system_ids)
    end

    # Register with character index
    if character_ids = subscription["character_ids"] do
      Logger.info(
        "[INFO] Registering subscription with CharacterIndex - " <>
          "subscription_id: #{subscription_id}, characters: #{inspect(character_ids)}"
      )

      CharacterIndex.add_subscription(subscription_id, character_ids)
    end
  end

  defp unregister_from_indexes(subscription) do
    subscription_id = subscription["id"]

    # Unregister from both indexes (they handle the cleanup internally)
    SystemIndex.remove_subscription(subscription_id)
    CharacterIndex.remove_subscription(subscription_id)
  end

  defp systems_or_characters_changed?(old_sub, new_sub) do
    old_systems = MapSet.new(old_sub["system_ids"] || [])
    new_systems = MapSet.new(new_sub["system_ids"] || [])
    old_chars = MapSet.new(old_sub["character_ids"] || [])
    new_chars = MapSet.new(new_sub["character_ids"] || [])

    not MapSet.equal?(old_systems, new_systems) or not MapSet.equal?(old_chars, new_chars)
  end

  defp send_webhook_notification(state, system_id, matching_kills) do
    # Send webhook notification asynchronously
    SupervisedTask.start_child(
      fn ->
        WebhookNotifier.notify_webhook(
          state.subscription["callback_url"],
          system_id,
          matching_kills,
          state.subscription_id
        )
      end,
      task_name: "webhook_notification",
      metadata: %{
        subscription_id: state.subscription_id,
        killmail_count: length(matching_kills)
      }
    )
  end

  defp send_to_websocket_channel(state, system_id, matching_kills) do
    # Get the socket process from the subscription
    socket_pid = state.subscription["socket_pid"]

    # Build the message in the format expected by the WebSocket channel
    message = %{
      type: :detailed_kill_update,
      solar_system_id: system_id,
      kills: matching_kills,
      timestamp: DateTime.utc_now()
    }

    # Send directly to the WebSocket process
    if Process.alive?(socket_pid) do
      send(socket_pid, message)

      Logger.info(
        "[INFO] Sent killmail update directly to WebSocket - " <>
          "subscription_id: #{state.subscription_id}, system_id: #{system_id}, " <>
          "killmail_count: #{length(matching_kills)}, " <>
          "socket_pid: #{inspect(socket_pid)}, user_id: #{state.subscription["user_id"]}"
      )
    else
      Logger.warning("[WARNING] WebSocket process no longer alive",
        subscription_id: state.subscription_id,
        socket_pid: inspect(socket_pid)
      )
    end
  end
end
