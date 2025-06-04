defmodule WandererKills.Cache.Supervisor do
  @moduledoc """
  Supervisor for managing cache instances.

  This supervisor manages the lifecycle of all cache instances:
  - :killmails_cache - For storing killmail data
  - :system_cache - For storing system-specific data
  - :esi_cache - For storing ESI API responses
  """

  use Supervisor
  require Logger
  alias WandererKills.Cache.Key

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("[Cache] Starting cache supervisor")

    children = [
      # Killmails cache with 24-hour TTL
      Supervisor.child_spec(
        {Cachex, name: :killmails_cache, ttl: Key.get_ttl(:killmails)},
        id: :killmails_cache
      ),
      # System cache with 1-hour TTL
      Supervisor.child_spec(
        {Cachex, name: :system_cache, ttl: Key.get_ttl(:system)},
        id: :system_cache
      ),
      # ESI cache with 48-hour TTL
      Supervisor.child_spec(
        {Cachex, name: :esi_cache, ttl: Key.get_ttl(:esi)},
        id: :esi_cache
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
