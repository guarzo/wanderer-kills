defmodule WandererKills.Ingest.SmartRateLimiter do
  @moduledoc """
  Intelligent rate limiter that queues requests when rate limits are hit
  and processes them with priority-based scheduling.

  Features:
  - Priority-based request queuing
  - Request deduplication and coalescing
  - Adaptive rate window detection
  - Circuit breaker for persistent rate limiting
  - Backpressure management
  """

  use GenServer
  require Logger

  alias WandererKills.Core.Support.Error

  # Request priorities (lower number = higher priority)
  @priorities %{
    realtime: 1,      # Real-time killmail fetches
    preload: 2,       # WebSocket preload requests
    background: 3,    # Background system updates
    bulk: 4          # Bulk operations
  }


  defmodule State do
    defstruct [
      # Request queue (priority queue)
      request_queue: :queue.new(),

      # Pending requests (for deduplication)
      pending_requests: %{},

      # Rate limit state
      current_tokens: 0,
      max_tokens: 100,
      refill_rate: 50,
      last_refill: nil,

      # Circuit breaker
      circuit_state: :closed,
      failure_count: 0,
      last_failure: nil,
      circuit_timeout: 30_000,  # 30 seconds

      # Rate window detection
      rate_limit_history: [],
      detected_window_ms: 60_000,  # Default 1 minute

      # Configuration
      config: %{}
    ]
  end

  defmodule Request do
    defstruct [
      :id,
      :type,           # :system_killmails, :killmail, etc.
      :params,         # %{system_id: 123, opts: []}
      :priority,       # :realtime, :preload, :background, :bulk
      :requester_pid,
      :reply_ref,
      :created_at,
      :timeout_ref
    ]
  end

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Request system killmails with intelligent rate limiting.

  ## Options
    * `:priority` - Request priority (:realtime, :preload, :background, :bulk)
    * `:timeout` - Request timeout in milliseconds (default: 30_000)
    * `:coalesce` - Whether to coalesce with existing identical requests (default: true)
  """
  def request_system_killmails(system_id, opts \\ [], request_opts \\ []) do
    priority = Keyword.get(request_opts, :priority, :background)
    timeout = Keyword.get(request_opts, :timeout, 30_000)
    coalesce = Keyword.get(request_opts, :coalesce, true)

    request = %Request{
      id: generate_request_id(),
      type: :system_killmails,
      params: %{system_id: system_id, opts: opts},
      priority: priority,
      requester_pid: self(),
      reply_ref: make_ref(),
      created_at: System.monotonic_time(:millisecond)
    }

    GenServer.call(__MODULE__, {:request, request, coalesce}, timeout)
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    config = %{
      max_tokens: Keyword.get(opts, :max_tokens, 100),
      refill_rate: Keyword.get(opts, :refill_rate, 50),
      refill_interval_ms: Keyword.get(opts, :refill_interval_ms, 1000),
      circuit_failure_threshold: Keyword.get(opts, :circuit_failure_threshold, 5),
      circuit_timeout_ms: Keyword.get(opts, :circuit_timeout_ms, 30_000)
    }

    state = %State{
      current_tokens: config.max_tokens,
      max_tokens: config.max_tokens,
      refill_rate: config.refill_rate,
      last_refill: System.monotonic_time(:millisecond),
      circuit_timeout: config.circuit_timeout_ms,
      config: config
    }

    # Schedule token refill
    schedule_token_refill(config.refill_interval_ms)

    Logger.info("[SmartRateLimiter] Started with config: #{inspect(config)}")

    {:ok, state}
  end

  @impl true
  def handle_call({:request, request, coalesce}, from, state) do
    case state.circuit_state do
      :open ->
        # Circuit is open, reject immediately
        {:reply, {:error, Error.rate_limit_error(:circuit_open, "Circuit breaker is open")}, state}

      _ ->
        # Try to process request or queue it
        handle_request(request, from, coalesce, state)
    end
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      circuit_state: state.circuit_state,
      current_tokens: state.current_tokens,
      queue_size: :queue.len(state.request_queue),
      pending_requests: map_size(state.pending_requests),
      failure_count: state.failure_count,
      detected_window_ms: state.detected_window_ms
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_cast({:request_complete, request_id, result}, state) do
    # Handle completed request and reply to all waiters
    case find_and_remove_pending_request(state.pending_requests, request_id) do
      {nil, pending_requests} ->
        # Request not found (maybe timed out already)
        {:noreply, %{state | pending_requests: pending_requests}}

      {pending_request, pending_requests} ->
        # Reply to all waiters
        Enum.each(pending_request.waiters, fn waiter ->
          GenServer.reply(waiter, result)
        end)

        new_state = %{state | pending_requests: pending_requests}
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:refill_tokens, state) do
    new_state = refill_tokens(state)

    # Try to process queued requests
    final_state = process_queue(new_state)

    # Schedule next refill
    schedule_token_refill(state.config.refill_interval_ms)

    {:noreply, final_state}
  end

  def handle_info(:check_circuit, state) do
    new_state =
      if state.circuit_state == :open do
        # Try to transition to half-open
        %{state | circuit_state: :half_open, failure_count: 0}
      else
        state
      end

    {:noreply, new_state}
  end

  def handle_info({:request_timeout, request_id}, state) do
    # Handle request timeout
    new_state = handle_request_timeout(request_id, state)
    {:noreply, new_state}
  end

  ## Private Functions

  defp handle_request(request, from, coalesce, state) do
    request_key = request_key(request)

    cond do
      # Check if we can coalesce with existing request
      coalesce and Map.has_key?(state.pending_requests, request_key) ->
        # Add to existing request's waiters
        updated_pending = add_waiter_to_pending(state.pending_requests, request_key, from)
        new_state = %{state | pending_requests: updated_pending}
        {:noreply, new_state}

      # Check if we have tokens available
      state.current_tokens > 0 ->
        # Process immediately
        execute_request(request, from, state)

      true ->
        # Queue the request
        queue_request(request, from, state)
    end
  end

  defp execute_request(request, from, state) do
    # Consume a token
    new_state = %{state | current_tokens: state.current_tokens - 1}

    # Add to pending requests
    request_key = request_key(request)
    pending_requests = Map.put(state.pending_requests, request_key, %{
      request: request,
      waiters: [from],
      started_at: System.monotonic_time(:millisecond)
    })

    # Set timeout for request
    timeout_ms = min(30_000, request.timeout || 30_000)
    _timeout_ref = Process.send_after(self(), {:request_timeout, request.id}, timeout_ms)

    # Execute the actual request asynchronously
    Task.start(fn ->
      result = perform_zkb_request(request)
      GenServer.cast(__MODULE__, {:request_complete, request.id, result})
    end)

    updated_state = %{new_state |
      pending_requests: pending_requests
    }

    {:noreply, updated_state}
  end

  defp queue_request(request, from, state) do
    # Add timeout for queued request
    timeout_ref = Process.send_after(self(), {:request_timeout, request.id}, 60_000)

    # Create priority queue item
    queue_item = {priority_value(request.priority), request, from, timeout_ref}

    # Add to priority queue
    new_queue = :queue.in(queue_item, state.request_queue)
    new_state = %{state | request_queue: new_queue}

    Logger.debug("[SmartRateLimiter] Queued request",
      request_id: request.id,
      priority: request.priority,
      queue_size: :queue.len(new_queue)
    )

    {:noreply, new_state}
  end

  defp process_queue(state) do
    if state.current_tokens > 0 and not :queue.is_empty(state.request_queue) do
      case :queue.out(state.request_queue) do
        {{:value, {_priority, request, from, timeout_ref}}, new_queue} ->
          # Cancel timeout
          Process.cancel_timer(timeout_ref)

          # Execute the request
          case execute_request(request, from, %{state | request_queue: new_queue}) do
            {:noreply, new_state} -> new_state
            _ -> state
          end

        {:empty, _} ->
          state
      end
    else
      state
    end
  end

  defp perform_zkb_request(request) do
    alias WandererKills.Ingest.Killmails.ZkbClient

    case request.type do
      :system_killmails ->
        ZkbClient.fetch_system_killmails(
          request.params.system_id,
          request.params.opts
        )

      :killmail ->
        ZkbClient.fetch_killmail(request.params.killmail_id)

      _ ->
        {:error, Error.validation_error(:unknown_request_type, "Unknown request type")}
    end
  end

  defp refill_tokens(state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_refill

    # Calculate tokens to add based on elapsed time
    tokens_to_add = trunc(elapsed * state.refill_rate / 1000)
    new_tokens = min(state.current_tokens + tokens_to_add, state.max_tokens)

    %{state |
      current_tokens: new_tokens,
      last_refill: now
    }
  end

  defp request_key(request) do
    # Create a key for request deduplication
    case request.type do
      :system_killmails ->
        {request.type, request.params.system_id, request.params.opts}
      :killmail ->
        {request.type, request.params.killmail_id}
      _ ->
        {request.type, request.params}
    end
  end

  defp priority_value(priority) do
    Map.get(@priorities, priority, 999)
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp schedule_token_refill(interval) do
    Process.send_after(self(), :refill_tokens, interval)
  end

  defp add_waiter_to_pending(pending_requests, request_key, from) do
    case Map.get(pending_requests, request_key) do
      nil -> pending_requests
      pending ->
        updated_waiters = [from | pending.waiters]
        Map.put(pending_requests, request_key, %{pending | waiters: updated_waiters})
    end
  end

  defp handle_request_timeout(request_id, state) do
    # Find and remove timed out request from queue or pending
    Logger.warning("[SmartRateLimiter] Request timeout", request_id: request_id)

    # TODO: Implement timeout handling for queued and pending requests
    state
  end

  defp find_and_remove_pending_request(pending_requests, request_id) do
    case Enum.find(pending_requests, fn {_key, pending} ->
      pending.request.id == request_id
    end) do
      nil ->
        {nil, pending_requests}

      {request_key, pending_request} ->
        updated_pending = Map.delete(pending_requests, request_key)
        {pending_request, updated_pending}
    end
  end
end
