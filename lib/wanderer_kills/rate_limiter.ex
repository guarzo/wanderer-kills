defmodule WandererKills.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for external API calls.

  Implements a token bucket algorithm to rate limit requests to external services
  like zkillboard and ESI APIs. Each service has its own bucket with configurable
  capacity and refill rate.
  """

  use GenServer
  require Logger

  @type service :: :zkillboard | :esi
  @type bucket_state :: %{
          tokens: float(),
          capacity: pos_integer(),
          refill_rate: pos_integer(),
          last_refill: integer()
        }

  # Default configurations
  @zkb_capacity 10
  # tokens per minute
  @zkb_refill_rate 10
  @esi_capacity 100
  # tokens per minute
  @esi_refill_rate 100

  # Public API

  @doc """
  Starts the rate limiter GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attempts to consume a token for the given service.
  Returns :ok if a token was available, {:error, :rate_limited} otherwise.
  """
  @spec check_rate_limit(service()) :: :ok | {:error, :rate_limited}
  def check_rate_limit(service) when service in [:zkillboard, :esi] do
    GenServer.call(__MODULE__, {:consume_token, service})
  end

  @doc """
  Gets the current state of a bucket (for monitoring/debugging).
  """
  @spec get_bucket_state(service()) :: bucket_state()
  def get_bucket_state(service) when service in [:zkillboard, :esi] do
    GenServer.call(__MODULE__, {:get_state, service})
  end

  @doc """
  Resets a bucket to full capacity (useful for testing).
  """
  @spec reset_bucket(service()) :: :ok
  def reset_bucket(service) when service in [:zkillboard, :esi] do
    GenServer.cast(__MODULE__, {:reset_bucket, service})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    zkb_capacity = Keyword.get(opts, :zkb_capacity, @zkb_capacity)
    zkb_refill_rate = Keyword.get(opts, :zkb_refill_rate, @zkb_refill_rate)
    esi_capacity = Keyword.get(opts, :esi_capacity, @esi_capacity)
    esi_refill_rate = Keyword.get(opts, :esi_refill_rate, @esi_refill_rate)

    state = %{
      zkillboard: %{
        tokens: zkb_capacity * 1.0,
        capacity: zkb_capacity,
        refill_rate: zkb_refill_rate,
        last_refill: System.monotonic_time(:millisecond)
      },
      esi: %{
        tokens: esi_capacity * 1.0,
        capacity: esi_capacity,
        refill_rate: esi_refill_rate,
        last_refill: System.monotonic_time(:millisecond)
      }
    }

    Logger.info("Rate limiter started",
      zkb_capacity: zkb_capacity,
      zkb_refill_rate: zkb_refill_rate,
      esi_capacity: esi_capacity,
      esi_refill_rate: esi_refill_rate
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:consume_token, service}, _from, state) do
    bucket = Map.get(state, service)

    # Refill tokens based on time elapsed
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - bucket.last_refill
    elapsed_minutes = elapsed_ms / 60_000

    tokens_to_add = elapsed_minutes * bucket.refill_rate
    new_tokens = min(bucket.tokens + tokens_to_add, bucket.capacity * 1.0)

    if new_tokens >= 1.0 do
      # Consume a token
      updated_bucket = %{bucket | tokens: new_tokens - 1.0, last_refill: now}

      new_state = Map.put(state, service, updated_bucket)

      {:reply, :ok, new_state}
    else
      # No tokens available
      updated_bucket = %{bucket | tokens: new_tokens, last_refill: now}

      new_state = Map.put(state, service, updated_bucket)

      Logger.warning("Rate limit exceeded",
        service: service,
        available_tokens: new_tokens,
        capacity: bucket.capacity
      )

      {:reply, {:error, :rate_limited}, new_state}
    end
  end

  @impl true
  def handle_call({:get_state, service}, _from, state) do
    bucket = Map.get(state, service)

    # Calculate current tokens with refill
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - bucket.last_refill
    elapsed_minutes = elapsed_ms / 60_000

    tokens_to_add = elapsed_minutes * bucket.refill_rate
    current_tokens = min(bucket.tokens + tokens_to_add, bucket.capacity * 1.0)

    bucket_info = %{bucket | tokens: current_tokens}

    {:reply, bucket_info, state}
  end

  @impl true
  def handle_cast({:reset_bucket, service}, state) do
    bucket = Map.get(state, service)

    updated_bucket = %{
      bucket
      | tokens: bucket.capacity * 1.0,
        last_refill: System.monotonic_time(:millisecond)
    }

    new_state = Map.put(state, service, updated_bucket)

    Logger.info("Bucket reset", service: service, tokens: bucket.capacity)

    {:noreply, new_state}
  end
end
