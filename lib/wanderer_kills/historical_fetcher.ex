defmodule WandererKills.HistoricalFetcher do
  @moduledoc """
  Manages historical killmail data fetching with rate limiting and progressive delivery.

  This GenServer handles extended preload requests for historical data, fetching
  killmails from zkillboard with rate limiting and delivering them progressively
  to WebSocket clients.
  """

  use GenServer
  require Logger

  alias WandererKills.{RateLimiter, SubscriptionManager}
  alias WandererKills.Killmails.{ZkbClient, UnifiedProcessor}
  alias WandererKills.Support.{SupervisedTask, Error}
  alias WandererKillsWeb.Endpoint

  @type preload_request :: %{
          subscription_id: String.t(),
          system_ids: [integer()],
          config: map(),
          status: atom(),
          progress: map()
        }

  # Default configuration
  @default_batch_size 10
  @default_delivery_interval 1000
  # Check queue every 5 seconds
  @process_interval 5000

  # Public API

  @doc """
  Starts the historical fetcher GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Requests historical data preload for a subscription.
  """
  @spec request_preload(String.t(), map()) :: :ok | {:error, term()}
  def request_preload(subscription_id, config) do
    GenServer.call(__MODULE__, {:request_preload, subscription_id, config})
  end

  @doc """
  Gets the current status of a preload request.
  """
  @spec get_preload_status(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_preload_status(subscription_id) do
    GenServer.call(__MODULE__, {:get_status, subscription_id})
  end

  @doc """
  Cancels a preload request.
  """
  @spec cancel_preload(String.t()) :: :ok
  def cancel_preload(subscription_id) do
    GenServer.cast(__MODULE__, {:cancel_preload, subscription_id})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic processing
    Process.send_after(self(), :process_queue, @process_interval)

    state = %{
      # subscription_id => preload_request
      requests: %{},
      # List of subscription_ids to process
      queue: [],
      # subscription_id => task_ref
      active_tasks: %{}
    }

    Logger.info("Historical fetcher started")

    {:ok, state}
  end

  @impl true
  def handle_call({:request_preload, subscription_id, config}, _from, state) do
    case get_subscription_from_manager(subscription_id) do
      {:ok, subscription} ->
        # Extract system IDs from subscription
        system_ids = Map.get(subscription, "system_ids", [])

        if length(system_ids) == 0 do
          {:reply, {:error, Error.validation_error(:no_systems, "No systems in subscription")},
           state}
        else
          # Create preload request
          request = %{
            subscription_id: subscription_id,
            system_ids: system_ids,
            config: normalize_config(config),
            status: :pending,
            progress: %{
              total_systems: length(system_ids),
              completed_systems: 0,
              current_system: nil,
              total_kills_fetched: 0,
              total_kills_delivered: 0,
              started_at: nil,
              errors: []
            }
          }

          # Add to state
          new_requests = Map.put(state.requests, subscription_id, request)
          new_queue = state.queue ++ [subscription_id]
          new_state = %{state | requests: new_requests, queue: new_queue}

          Logger.info("Preload request added",
            subscription_id: subscription_id,
            systems: length(system_ids),
            config: config
          )

          {:reply, :ok, new_state}
        end

      {:error, _} ->
        {:reply, {:error, Error.not_found_error("subscription", "Subscription not found")}, state}
    end
  end

  @impl true
  def handle_call({:get_status, subscription_id}, _from, state) do
    case Map.get(state.requests, subscription_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      request ->
        status = %{
          status: request.status,
          progress: request.progress,
          config: request.config
        }

        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_cast({:cancel_preload, subscription_id}, state) do
    # Cancel active task if any
    case Map.get(state.active_tasks, subscription_id) do
      nil -> :ok
      task_ref -> Process.demonitor(task_ref, [:flush])
    end

    # Remove from queue and requests
    new_queue = Enum.reject(state.queue, &(&1 == subscription_id))
    new_requests = Map.delete(state.requests, subscription_id)
    new_active_tasks = Map.delete(state.active_tasks, subscription_id)

    new_state = %{
      state
      | queue: new_queue,
        requests: new_requests,
        active_tasks: new_active_tasks
    }

    Logger.info("Preload cancelled", subscription_id: subscription_id)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_progress, subscription_id, system_id, kills_fetched}, state) do
    new_requests =
      case Map.get(state.requests, subscription_id) do
        nil ->
          state.requests

        request ->
          updated_progress =
            request.progress
            |> Map.update(:completed_systems, 0, &(&1 + 1))
            |> Map.update(:total_kills_fetched, 0, &(&1 + kills_fetched))
            |> Map.put(:current_system, system_id)

          updated_request = %{request | progress: updated_progress}
          Map.put(state.requests, subscription_id, updated_request)
      end

    {:noreply, %{state | requests: new_requests}}
  end

  @impl true
  def handle_info(:process_queue, state) do
    # Process next item in queue if we have capacity
    new_state = process_next_in_queue(state)

    # Schedule next check
    Process.send_after(self(), :process_queue, @process_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:task_completed, subscription_id, result}, state) do
    # Remove from active tasks
    new_active_tasks = Map.delete(state.active_tasks, subscription_id)

    # Update request status
    new_requests =
      case Map.get(state.requests, subscription_id) do
        nil ->
          state.requests

        request ->
          updated_request =
            case result do
              :ok ->
                %{request | status: :completed}

              {:error, reason} ->
                progress = Map.update(request.progress, :errors, [reason], &(&1 ++ [reason]))
                %{request | status: :failed, progress: progress}
            end

          Map.put(state.requests, subscription_id, updated_request)
      end

    new_state = %{state | active_tasks: new_active_tasks, requests: new_requests}

    # Send completion notification
    send_preload_complete(subscription_id, Map.get(new_requests, subscription_id))

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Task crashed - will be handled by SupervisedTask telemetry
    {:noreply, state}
  end

  # Private functions

  defp normalize_config(config) do
    %{
      "enabled" => Map.get(config, "enabled", true),
      "limit_per_system" => Map.get(config, "limit_per_system", 100),
      "since_hours" => Map.get(config, "since_hours", 168),
      "delivery_batch_size" => Map.get(config, "delivery_batch_size", @default_batch_size),
      "delivery_interval_ms" =>
        Map.get(config, "delivery_interval_ms", @default_delivery_interval)
    }
  end

  defp process_next_in_queue(state) do
    # Check if we have capacity (no more than 3 active tasks)
    if map_size(state.active_tasks) >= 3 do
      state
    else
      case state.queue do
        [] ->
          state

        [subscription_id | rest_queue] ->
          case Map.get(state.requests, subscription_id) do
            nil ->
              # Request was cancelled
              %{state | queue: rest_queue}

            request ->
              # Start processing this request
              task = start_preload_task(request)

              # Update state
              new_active_tasks = Map.put(state.active_tasks, subscription_id, task.ref)

              new_requests =
                Map.put(state.requests, subscription_id, %{
                  request
                  | status: :processing,
                    progress: Map.put(request.progress, :started_at, DateTime.utc_now())
                })

              %{state | queue: rest_queue, active_tasks: new_active_tasks, requests: new_requests}
          end
      end
    end
  end

  defp start_preload_task(request) do
    parent = self()
    subscription_id = request.subscription_id

    SupervisedTask.start_child(
      fn ->
        result = do_preload(request)
        send(parent, {:task_completed, subscription_id, result})
        result
      end,
      task_name: "historical_preload",
      metadata: %{
        subscription_id: subscription_id,
        systems: length(request.system_ids)
      }
    )
  end

  defp do_preload(request) do
    Logger.info("Starting historical preload",
      subscription_id: request.subscription_id,
      systems: length(request.system_ids)
    )

    # Calculate time range
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -request.config["since_hours"] * 3600, :second)

    # Process each system
    Enum.reduce_while(request.system_ids, :ok, fn system_id, _acc ->
      case fetch_and_deliver_system(request, system_id, start_time, end_time) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.error("Failed to preload system",
            subscription_id: request.subscription_id,
            system_id: system_id,
            error: reason
          )

          {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_and_deliver_system(request, system_id, start_time, end_time) do
    # Update progress
    send_preload_status(request.subscription_id, %{
      status: "fetching",
      current_system: system_id,
      systems_complete: request.progress.completed_systems,
      total_systems: request.progress.total_systems
    })

    # Fetch killmails with pagination
    fetch_opts = [
      start_time: DateTime.to_iso8601(start_time),
      end_time: DateTime.to_iso8601(end_time),
      # Max per page
      limit: 200
    ]

    # Use a process dictionary or agent to track state across callbacks
    buffer_pid = spawn_link(fn -> buffer_loop([], 0) end)

    result =
      ZkbClient.fetch_system_killmails_paginated(system_id, fetch_opts, fn page_kills ->
        # Check rate limit before each page
        case RateLimiter.check_rate_limit(:zkillboard) do
          :ok ->
            # Process and buffer kills
            processed_kills = process_killmails(page_kills)

            # Update buffer
            send(buffer_pid, {:add_kills, processed_kills, self()})

            receive do
              {:buffer_state, buffer, _count} ->
                # Deliver in batches
                {to_deliver, remaining} =
                  Enum.split(buffer, request.config["delivery_batch_size"])

                if length(to_deliver) > 0 do
                  deliver_batch(request.subscription_id, to_deliver)

                  # Rate limit delivery
                  Process.sleep(request.config["delivery_interval_ms"])
                end

                # Update buffer with remaining
                send(buffer_pid, {:set_buffer, remaining})
            end

          {:error, :rate_limited} ->
            # Wait and retry
            Logger.warning("Rate limited, waiting 60 seconds", system_id: system_id)
            Process.sleep(60_000)
            :retry
        end
      end)

    # Get final state and deliver any remaining kills
    send(buffer_pid, {:get_final, self()})

    receive do
      {:final_state, final_buffer, total_fetched} ->
        if length(final_buffer) > 0 do
          deliver_batch(request.subscription_id, final_buffer)
        end

        # Update progress
        update_progress_async(request.subscription_id, system_id, total_fetched)
    end

    # Clean up
    Process.exit(buffer_pid, :normal)

    result
  end

  defp process_killmails(killmails) do
    # Process killmails through the unified processor
    killmails
    |> Enum.map(fn killmail ->
      case UnifiedProcessor.process_killmail(killmail, source: :historical_preload) do
        {:ok, processed} -> processed
        _ -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp deliver_batch(subscription_id, kills) do
    # Use Phoenix PubSub to broadcast to the subscription's topic
    # The WebSocket channel will handle delivery if connected
    Endpoint.broadcast("killmails:#{subscription_id}", "preload_batch", %{
      kills: kills,
      batch_size: length(kills)
    })
  end

  defp send_preload_status(subscription_id, status) do
    Endpoint.broadcast("killmails:#{subscription_id}", "preload_status", status)
  end

  defp send_preload_complete(subscription_id, request) do
    status = %{
      total_kills: request.progress.total_kills_delivered,
      systems_processed: request.progress.completed_systems,
      errors: request.progress.errors
    }

    Endpoint.broadcast("killmails:#{subscription_id}", "preload_complete", status)
  end

  defp get_subscription_from_manager(subscription_id) do
    # Get all subscriptions and find the matching one
    all_subs = SubscriptionManager.list_subscriptions()

    sub =
      Enum.find(all_subs, fn s ->
        Map.get(s, "id") == subscription_id ||
          Map.get(s, :id) == subscription_id
      end)

    if sub, do: {:ok, sub}, else: {:error, :not_found}
  end

  defp buffer_loop(buffer, count) do
    receive do
      {:add_kills, new_kills, from} ->
        new_buffer = buffer ++ new_kills
        new_count = count + length(new_kills)
        send(from, {:buffer_state, new_buffer, new_count})
        buffer_loop(new_buffer, new_count)

      {:set_buffer, new_buffer} ->
        buffer_loop(new_buffer, count)

      {:get_final, from} ->
        send(from, {:final_state, buffer, count})
    end
  end

  defp update_progress_async(subscription_id, system_id, kills_fetched) do
    GenServer.cast(__MODULE__, {:update_progress, subscription_id, system_id, kills_fetched})
  end
end
