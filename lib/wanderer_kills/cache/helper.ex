defmodule WandererKills.Cache.Helper do
  @moduledoc """
  Simplified cache operations with a single, consistent API.

  This module provides a unified interface for all cache operations,
  eliminating duplicate methods and providing clear, consistent patterns.

  ## Usage

  All cache operations follow the same pattern:
  - `get(namespace, id)` - Get a value
  - `put(namespace, id, value)` - Store a value
  - `delete(namespace, id)` - Delete a value
  - `exists?(namespace, id)` - Check if key exists

  ## Namespaces

  - `:killmails` - Killmail data
  - `:systems` - System-related data (killmails, timestamps, active list)
  - `:characters` - Character information
  - `:corporations` - Corporation information
  - `:alliances` - Alliance information
  - `:ship_types` - Ship type data
  """

  require Logger
  alias WandererKills.Support.Error

  @cache_name :wanderer_cache

  # Get the cache adapter from config, default to Cachex for compatibility
  defp cache_adapter do
    Application.get_env(:wanderer_kills, :cache_adapter, Cachex)
  end

  # Namespace configurations with TTLs
  @namespace_config %{
    killmails: %{ttl: :timer.minutes(5), prefix: "killmails"},
    systems: %{ttl: :timer.hours(1), prefix: "systems"},
    characters: %{ttl: :timer.hours(24), prefix: "esi:characters"},
    corporations: %{ttl: :timer.hours(24), prefix: "esi:corporations"},
    alliances: %{ttl: :timer.hours(24), prefix: "esi:alliances"},
    ship_types: %{ttl: :timer.hours(24), prefix: "esi:ship_types"},
    groups: %{ttl: :timer.hours(24), prefix: "esi:groups"}
  }

  @type namespace ::
          :killmails | :systems | :characters | :corporations | :alliances | :ship_types | :groups
  @type id :: String.t() | integer()
  @type value :: any()
  @type error :: {:error, Error.t()}

  # ============================================================================
  # Core Operations
  # ============================================================================

  @doc """
  Get a value from cache.

  Returns `{:ok, value}` if found, `{:error, %Error{}}` if not found.
  """
  @spec get(namespace(), id()) :: {:ok, value()} | error()
  def get(namespace, id) when is_atom(namespace) do
    key = build_key(namespace, id)

    case cache_adapter().get(@cache_name, key) do
      {:ok, nil} ->
        {:error, Error.cache_error(:not_found, "Key not found", %{namespace: namespace, id: id})}

      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("Cache get failed", namespace: namespace, id: id, error: reason)
        {:error, Error.cache_error(:get_failed, "Failed to get from cache", %{reason: reason})}
    end
  end

  @doc """
  Store a value in cache with namespace-specific TTL.
  """
  @spec put(namespace(), id(), value()) :: {:ok, boolean()} | error()
  def put(namespace, id, value) when is_atom(namespace) do
    key = build_key(namespace, id)
    ttl = get_ttl(namespace)

    case cache_adapter().put(@cache_name, key, value, ttl: ttl) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        Logger.error("Cache put failed", namespace: namespace, id: id, error: reason)
        {:error, Error.cache_error(:put_failed, "Failed to put to cache", %{reason: reason})}
    end
  end

  @doc """
  Delete a value from cache.
  """
  @spec delete(namespace(), id()) :: {:ok, boolean()} | error()
  def delete(namespace, id) when is_atom(namespace) do
    key = build_key(namespace, id)

    case cache_adapter().del(@cache_name, key) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        Logger.error("Cache delete failed", namespace: namespace, id: id, error: reason)

        {:error,
         Error.cache_error(:delete_failed, "Failed to delete from cache", %{reason: reason})}
    end
  end

  @doc """
  Check if a key exists in cache.
  """
  @spec exists?(namespace(), id()) :: boolean()
  def exists?(namespace, id) when is_atom(namespace) do
    key = build_key(namespace, id)

    case cache_adapter().exists?(@cache_name, key) do
      {:ok, exists} -> exists
      _ -> false
    end
  end

  @doc """
  Get a value or set it if not found.
  """
  @spec get_or_set(namespace(), id(), (-> value())) :: {:ok, value()} | error()
  def get_or_set(namespace, id, value_fn) when is_atom(namespace) and is_function(value_fn, 0) do
    case get(namespace, id) do
      {:ok, value} ->
        {:ok, value}

      {:error, %Error{type: :not_found}} ->
        value = value_fn.()
        put(namespace, id, value)
        {:ok, value}

      error ->
        error
    end
  end

  # ============================================================================
  # System-Specific Operations
  # ============================================================================

  @doc """
  List killmail IDs for a system.
  """
  @spec list_system_killmails(integer()) :: {:ok, [integer()]} | error()
  def list_system_killmails(system_id) do
    get(:systems, "killmails:#{system_id}")
  end

  @doc """
  Add a killmail ID to a system's list.
  """
  @spec add_system_killmail(integer(), integer()) :: {:ok, boolean()} | error()
  def add_system_killmail(system_id, killmail_id) do
    case list_system_killmails(system_id) do
      {:ok, existing_ids} when is_list(existing_ids) ->
        if killmail_id in existing_ids do
          {:ok, true}
        else
          put(:systems, "killmails:#{system_id}", [killmail_id | existing_ids])
        end

      {:error, %Error{type: :not_found}} ->
        put(:systems, "killmails:#{system_id}", [killmail_id])

      {:ok, _invalid_data} ->
        # Handle corrupted data by starting fresh
        Logger.warning("Corrupted system killmail data found, resetting", system_id: system_id)
        put(:systems, "killmails:#{system_id}", [killmail_id])

      error ->
        error
    end
  end

  @doc """
  Mark a system as having been fetched.
  """
  @spec mark_system_fetched(integer(), DateTime.t()) :: {:ok, boolean()} | error()
  def mark_system_fetched(system_id, timestamp \\ DateTime.utc_now()) do
    put(:systems, "last_fetch:#{system_id}", timestamp)
  end

  @doc """
  Check if a system was fetched within the given time window.
  """
  @spec system_fetched_recently?(integer(), integer()) :: boolean()
  def system_fetched_recently?(system_id, within_seconds \\ 3600) do
    case get(:systems, "last_fetch:#{system_id}") do
      {:ok, last_fetch} when is_struct(last_fetch, DateTime) ->
        DateTime.diff(DateTime.utc_now(), last_fetch) <= within_seconds

      _ ->
        false
    end
  end

  @doc """
  Get list of active systems.
  """
  @spec get_active_systems() :: {:ok, [integer()]} | error()
  def get_active_systems do
    case get(:systems, "active_list") do
      {:ok, systems} -> {:ok, systems}
      {:error, %Error{type: :not_found}} -> {:ok, []}
      error -> error
    end
  end

  @doc """
  Add a system to the active list.
  """
  @spec add_active_system(integer()) :: {:ok, boolean()} | error()
  def add_active_system(system_id) do
    case get_active_systems() do
      {:ok, systems} ->
        if system_id in systems do
          {:ok, true}
        else
          put(:systems, "active_list", [system_id | systems])
        end

      error ->
        error
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_key(namespace, id) do
    config = @namespace_config[namespace]
    "#{config.prefix}:#{to_string(id)}"
  end

  defp get_ttl(namespace) do
    @namespace_config[namespace].ttl
  end
end
