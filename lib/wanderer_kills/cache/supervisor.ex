defmodule WandererKills.Cache.Supervisor do
  @moduledoc """
  Supervisor for managing the unified cache instance.

  This supervisor manages a single Cachex instance that handles all cache types
  using namespaced keys:
  - killmails:* - For storing killmail data
  - system:* - For storing system-specific data
  - esi:* - For storing ESI API responses

  This approach reduces OTP process overhead while maintaining logical separation
  through key namespacing.
  """

  use Supervisor
  require Logger
  alias WandererKills.Cache.Key

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Logger.info("[Cache] Starting unified cache supervisor")

    children = [
      # Single unified cache instance with namespaced keys
      # Use the longest TTL (24 hours) and manage per-type TTLs at the application level
      Supervisor.child_spec(
        {Cachex, name: :unified_cache, ttl: Key.get_ttl(:killmails)},
        id: :unified_cache
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
