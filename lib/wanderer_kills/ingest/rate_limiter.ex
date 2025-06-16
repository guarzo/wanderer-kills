defmodule WandererKills.Ingest.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for external API calls.

  Implements a token bucket algorithm to rate limit requests to external services
  like zkillboard and ESI APIs. Each service has its own bucket with configurable
  capacity and refill rate.
  """

  use GenServer
  require Logger
  alias WandererKills.Core.Support.Error

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
  Returns :ok if a token was available, {:error, Error.t()} otherwise.
  """
  @spec check_rate_limit(service()) :: :ok | {:error, Error.t()}
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

    # Schedule periodic token refill every second
    Process.send_after(self(), :refill_tokens, 1_000)

    {:ok, state}
  end

  @impl true
  def handle_call({:consume_token, service}, _from, state) do
    bucket = Map.get(state, service)

    if bucket.tokens >= 1.0 do
      # Consume a token
      updated_bucket = %{bucket | tokens: bucket.tokens - 1.0}
      new_state = Map.put(state, service, updated_bucket)

      # Emit telemetry for successful token consumption
      :telemetry.execute(
        [:wanderer_kills, :rate_limiter, :token_consumed],
        %{tokens_remaining: updated_bucket.tokens},
        %{service: service}
      )

      {:reply, :ok, new_state}
    else
      # No tokens available
      Logger.warning("Rate limit exceeded",
        service: service,
        available_tokens: bucket.tokens,
        capacity: bucket.capacity
      )

      # Emit telemetry for rate limit exceeded
      :telemetry.execute(
        [:wanderer_kills, :rate_limiter, :rate_limited],
        %{tokens_available: bucket.tokens},
        %{service: service}
      )

      {:reply, {:error, Error.rate_limit_error("Rate limit exceeded for #{service}", %{service: service, tokens_available: bucket.tokens})}, state}
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

  @impl true
  def handle_info(:refill_tokens, state) do
    now = System.monotonic_time(:millisecond)

    new_state =
      Enum.reduce(state, %{}, fn {service, bucket}, acc ->
        elapsed_ms = now - bucket.last_refill
        elapsed_minutes = elapsed_ms / 60_000

        tokens_to_add = elapsed_minutes * bucket.refill_rate
        new_tokens = min(bucket.tokens + tokens_to_add, bucket.capacity * 1.0)

        updated_bucket = %{bucket | tokens: new_tokens, last_refill: now}
        Map.put(acc, service, updated_bucket)
      end)

    # Schedule next refill
    Process.send_after(self(), :refill_tokens, 1_000)

    {:noreply, new_state}
  end
end
