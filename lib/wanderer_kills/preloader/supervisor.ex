defmodule WandererKills.PreloaderSupervisor do
  @moduledoc """
  Supervisor for the Preloader subsystem.
  Manages the lifecycle of the Preloader and Redisq processes.
  """

  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      WandererKills.Preloader.Worker,
      %{
        id: WandererKills.External.ZKB.RedisQ,
        start: {WandererKills.External.ZKB.RedisQ, :start_link, []},
        restart: :permanent,
        type: :worker,
        timeout: :timer.seconds(30)
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
