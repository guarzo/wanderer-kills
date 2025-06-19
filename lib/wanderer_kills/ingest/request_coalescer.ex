defmodule WandererKills.Ingest.RequestCoalescer do
  @moduledoc """
  Coalesces identical requests to reduce API calls and share results
  among multiple requesters.
  
  When multiple WebSocket clients request the same system data simultaneously,
  this module ensures only one API call is made and the result is shared.
  """
  
  use GenServer
  require Logger
  
  defmodule PendingRequest do
    defstruct [
      :request_key,
      :requesters,      # List of {pid, ref} tuples
      :started_at,
      :timeout_ref,
      :executing_pid
    ]
  end
  
  defmodule State do
    defstruct [
      pending_requests: %{},
      request_timeout_ms: 30_000
    ]
  end
  
  ## Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Request data with automatic coalescing.
  Returns {:ok, data} or {:error, reason}
  """
  def request(request_key, executor_fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(__MODULE__, {:request, request_key, executor_fun}, timeout)
  end
  
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  ## GenServer Callbacks
  
  @impl true
  def init(opts) do
    request_timeout_ms = Keyword.get(opts, :request_timeout_ms, 30_000)
    
    state = %State{
      request_timeout_ms: request_timeout_ms
    }
    
    Logger.info("[RequestCoalescer] Started")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:request, request_key, executor_fun}, from, state) do
    case Map.get(state.pending_requests, request_key) do
      nil ->
        # New request - start execution
        start_new_request(request_key, executor_fun, from, state)
        
      existing ->
        # Coalesce with existing request
        add_to_existing_request(existing, from, state)
    end
  end
  
  def handle_call(:get_stats, _from, state) do
    stats = %{
      pending_requests: map_size(state.pending_requests),
      total_requesters: total_requesters(state.pending_requests)
    }
    
    {:reply, {:ok, stats}, state}
  end
  
  @impl true
  def handle_info({:request_complete, request_key, result}, state) do
    case Map.get(state.pending_requests, request_key) do
      nil ->
        # Request already timed out or completed
        {:noreply, state}
        
      pending ->
        # Reply to all waiters
        Enum.each(pending.requesters, fn from ->
          GenServer.reply(from, result)
        end)
        
        # Cancel timeout and remove from pending
        if pending.timeout_ref do
          Process.cancel_timer(pending.timeout_ref)
        end
        
        new_pending = Map.delete(state.pending_requests, request_key)
        
        Logger.debug("[RequestCoalescer] Request completed",
          request_key: inspect(request_key),
          requesters_count: length(pending.requesters)
        )
        
        {:noreply, %{state | pending_requests: new_pending}}
    end
  end
  
  def handle_info({:request_timeout, request_key}, state) do
    case Map.get(state.pending_requests, request_key) do
      nil ->
        {:noreply, state}
        
      pending ->
        # Reply with timeout error to all waiters
        timeout_error = {:error, :timeout}
        Enum.each(pending.requesters, fn from ->
          GenServer.reply(from, timeout_error)
        end)
        
        new_pending = Map.delete(state.pending_requests, request_key)
        
        Logger.warning("[RequestCoalescer] Request timeout",
          request_key: inspect(request_key),
          requesters_count: length(pending.requesters)
        )
        
        {:noreply, %{state | pending_requests: new_pending}}
    end
  end
  
  ## Private Functions
  
  defp start_new_request(request_key, executor_fun, from, state) do
    timeout_ref = Process.send_after(
      self(), 
      {:request_timeout, request_key}, 
      state.request_timeout_ms
    )
    
    # Start async execution
    executing_pid = spawn_link(fn ->
      result = executor_fun.()
      send(__MODULE__, {:request_complete, request_key, result})
    end)
    
    pending = %PendingRequest{
      request_key: request_key,
      requesters: [from],
      started_at: System.monotonic_time(:millisecond),
      timeout_ref: timeout_ref,
      executing_pid: executing_pid
    }
    
    new_pending = Map.put(state.pending_requests, request_key, pending)
    
    Logger.debug("[RequestCoalescer] Started new request", 
      request_key: inspect(request_key)
    )
    
    {:noreply, %{state | pending_requests: new_pending}}
  end
  
  defp add_to_existing_request(existing, from, state) do
    updated_requesters = [from | existing.requesters]
    updated_pending = %{existing | requesters: updated_requesters}
    
    new_pending = Map.put(state.pending_requests, existing.request_key, updated_pending)
    
    Logger.debug("[RequestCoalescer] Added to existing request",
      request_key: inspect(existing.request_key),
      total_requesters: length(updated_requesters)
    )
    
    {:noreply, %{state | pending_requests: new_pending}}
  end
  
  defp total_requesters(pending_requests) do
    pending_requests
    |> Map.values()
    |> Enum.reduce(0, fn pending, acc -> acc + length(pending.requesters) end)
  end
end