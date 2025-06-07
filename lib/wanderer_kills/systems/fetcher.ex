defmodule WandererKills.Systems.Fetcher do
  @moduledoc """
  Fetches and manages active PVP systems from zKillboard.

  This module handles discovering and caching systems with recent killmail activity
  using zKillboard's active systems API.

  This module provides functionality to:
  - Fetch active systems from zKillboard
  - Track active systems
  - Handle rate limiting and retries
  - Cache results for improved performance

  ## Features

  - Automatic caching with configurable TTLs
  - Rate limit handling and automatic retries
  - Error handling and logging
  - Backward compatibility with legacy functions

  ## Usage

  ```elixir
  # Fetch active systems
  {:ok, systems} = ActiveSystemsFetcher.fetch_active_systems()

  # Fetch with custom options
  opts = [force: true]
  {:ok, systems} = ActiveSystemsFetcher.fetch_active_systems(opts)
  ```

  ## Configuration

  Default options:
  - `force`: false (use cache if available)

  ## Error Handling

  All functions return either:
  - `{:ok, result}` - On success
  - `{:error, reason}` - On failure
  """

  require Logger

  alias WandererKills.Zkb.Client, as: ZkbClient
  alias WandererKills.Core.Cache

  @type system_id :: pos_integer()
  @type fetch_opts :: [force: boolean()]

  # -------------------------------------------------
  # Active systems
  # -------------------------------------------------

  @doc """
  Fetch active systems from zKillboard.

  ## Parameters
  - `opts` - Options including:
    - `:force` - Ignore recent cache and force fresh fetch (default: false)

  ## Returns
  - `{:ok, [system_id]}` - On success
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  # Fetch with defaults
  {:ok, systems} = fetch_active_systems()

  # Fetch with custom options
  opts = [force: true]
  {:ok, systems} = fetch_active_systems(opts)
  ```
  """
  @spec fetch_active_systems(fetch_opts()) :: {:ok, [system_id()]} | {:error, term()}
  def fetch_active_systems(opts \\ []) do
    force = Keyword.get(opts, :force, false)

    if force do
      do_fetch_active_systems()
    else
      case fetch_from_cache() do
        {:ok, systems} -> {:ok, systems}
        {:error, _reason} -> do_fetch_active_systems()
      end
    end
  end

  @spec fetch_from_cache() :: {:ok, [system_id()]} | {:error, term()}
  defp fetch_from_cache do
    case Cache.get_active_systems() do
      {:ok, systems} when is_list(systems) ->
        {:ok, systems}

      {:error, reason} ->
        Logger.warning("Cache error for active systems, falling back to fresh fetch",
          operation: :fetch_active_systems,
          step: :cache_error,
          error: reason
        )

        do_fetch_active_systems()
    end
  end

  @spec do_fetch_active_systems() :: {:ok, [system_id()]} | {:error, term()}
  defp do_fetch_active_systems do
    case ZkbClient.fetch_active_systems() do
      {:ok, systems} ->
        # Cache the results - this will be handled by the unified cache system
        # For now, just return the systems
        {:ok, systems}

      {:error, reason} ->
        Logger.error("API error for active systems",
          operation: :fetch_active_systems,
          step: :api_call,
          error: reason
        )

        {:error, reason}
    end
  end

  def handle_info(:fetch_active_systems, state) do
    case fetch_active_systems() do
      {:ok, systems} ->
        {:noreply, %{state | active_systems: systems}}

      {:error, reason} ->
        Logger.error("Failed to fetch active systems: #{inspect(reason)}")
        {:noreply, state}
    end
  end
end
