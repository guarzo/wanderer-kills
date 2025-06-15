defmodule WandererKills.Subs.SubscriptionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing subscription worker processes.

  Each subscription is supervised individually, providing fault tolerance.
  When a subscription worker crashes, it can be restarted independently
  without affecting other subscriptions.
  """

  use DynamicSupervisor
  require Logger

  alias WandererKills.Subs.SubscriptionWorker

  @type subscription_id :: String.t()

  # ============================================================================
  # Client API  
  # ============================================================================

  @doc """
  Starts the subscription supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(init_args) do
    DynamicSupervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @doc """
  Starts a new subscription worker.
  """
  @spec start_subscription(map()) :: DynamicSupervisor.on_start_child()
  def start_subscription(subscription) do
    child_spec = {SubscriptionWorker, subscription}

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} = result ->
        Logger.debug("[DEBUG] Started subscription worker",
          subscription_id: subscription["id"],
          pid: inspect(pid)
        )

        result

      {:error, {:already_started, pid}} ->
        Logger.debug("[DEBUG] Subscription worker already running",
          subscription_id: subscription["id"],
          pid: inspect(pid)
        )

        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("[ERROR] Failed to start subscription worker",
          subscription_id: subscription["id"],
          error: inspect(reason)
        )

        error
    end
  end

  @doc """
  Stops a subscription worker.
  """
  @spec stop_subscription(subscription_id()) :: :ok | {:error, :not_found}
  def stop_subscription(subscription_id) do
    case SubscriptionWorker.lookup_subscription(subscription_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

        Logger.debug("[DEBUG] Stopped subscription worker",
          subscription_id: subscription_id,
          pid: inspect(pid)
        )

        :ok

      :error ->
        Logger.debug("[DEBUG] Subscription worker not found",
          subscription_id: subscription_id
        )

        {:error, :not_found}
    end
  end

  @doc """
  Lists all running subscription workers.
  """
  @spec list_subscriptions() :: [subscription_id()]
  def list_subscriptions do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      case SubscriptionWorker.get_subscription_id(pid) do
        {:ok, subscription_id} -> subscription_id
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  @doc """
  Gets statistics about running subscription workers.
  """
  @spec get_stats() :: map()
  def get_stats do
    children = DynamicSupervisor.which_children(__MODULE__)

    stats =
      Enum.reduce(children, %{total: 0, webhook: 0, websocket: 0}, fn
        {_, pid, _, _}, acc when is_pid(pid) ->
          type =
            case SubscriptionWorker.get_subscription_type(pid) do
              {:ok, type} -> type
              _ -> :unknown
            end

          %{
            acc
            | total: acc.total + 1,
              webhook: if(type == :webhook, do: acc.webhook + 1, else: acc.webhook),
              websocket: if(type == :websocket, do: acc.websocket + 1, else: acc.websocket)
          }

        _, acc ->
          acc
      end)

    Map.put(stats, :active_workers, stats.total)
  end

  @doc """
  Counts the number of running subscription workers.
  """
  @spec count_subscriptions() :: non_neg_integer()
  def count_subscriptions do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  # ============================================================================
  # Supervisor Callbacks
  # ============================================================================

  @impl true
  def init(_init_args) do
    Logger.info("[INFO] SubscriptionSupervisor starting")

    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 30
    )
  end
end
