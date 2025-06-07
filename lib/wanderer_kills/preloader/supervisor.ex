defmodule WandererKills.PreloaderSupervisor do
  @moduledoc """
  Supervisor for the Preloader subsystem.
  Manages the lifecycle of the Preloader and RedisQ processes.
  """

  use Supervisor
  alias WandererKills.Infrastructure.Config

  # No @impl here, since Supervisor only defines init/1 as a callback.
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  @spec init(any()) ::
          {:ok,
           {%{
              :strategy => :one_for_one,
              :intensity => non_neg_integer(),
              :period => pos_integer(),
              :auto_shutdown => :all_significant | :any_significant | :never
            }, [Supervisor.child_spec()]}}
  def init(_opts) do
    # Build children list based on configuration
    children = []

    # Always include preloader worker
    preloader_worker_spec = Supervisor.child_spec(WandererKills.Preloader.Worker, [])
    children = [preloader_worker_spec | children]

    # Conditionally add RedisQ based on configuration
    children =
      if Config.start_redisq?() do
        redisq_spec = %{
          id: WandererKills.External.ZKB.RedisQ,
          start: {WandererKills.External.ZKB.RedisQ, :start_link, []},
          restart: :permanent,
          type: :worker,
          timeout: :timer.seconds(30)
        }

        [redisq_spec | children]
      else
        children
      end

    # Reverse to maintain proper order (preloader first, then RedisQ)
    children = Enum.reverse(children)

    # Supervisor flags with better fault tolerance
    flags = %{
      strategy: :one_for_one,
      # Allow up to 3 restarts
      intensity: 3,
      # Within 60 seconds
      period: 60,
      auto_shutdown: :any_significant
    }

    {:ok, {flags, children}}
  end
end
