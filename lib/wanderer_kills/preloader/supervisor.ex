defmodule WandererKills.PreloaderSupervisor do
  @moduledoc """
  Supervisor for the Preloader subsystem.
  Manages the lifecycle of the Preloader and RedisQ processes.
  """

  use Supervisor

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
    # 1) Turn the Preloader.Worker module into a proper child-spec map.
    preloader_worker_spec =
      Supervisor.child_spec(WandererKills.Preloader.Worker, [])

    # 2) Keep your existing map for RedisQ:
    redisq_spec = %{
      id: WandererKills.External.ZKB.RedisQ,
      start: {WandererKills.External.ZKB.RedisQ, :start_link, []},
      restart: :permanent,
      type: :worker,
      timeout: :timer.seconds(30)
    }

    children = [
      preloader_worker_spec,
      redisq_spec
    ]

    # 3) A concrete flags map that matches Supervisor’s callback contract:
    flags = %{
      strategy: :one_for_one,
      intensity: 1,
      period: 5,
      auto_shutdown: :any_significant
    }

    {:ok, {flags, children}}
  end
end
