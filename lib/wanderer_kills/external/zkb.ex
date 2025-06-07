defmodule WandererKills.External.ZKB do
  @moduledoc """
  External ZKB API service with telemetry and processing.

  This module consolidates ZKB API interactions with telemetry, logging,
  and processing functionality. It replaces the previous fetching architecture
  with a more direct approach.
  """

  require Logger
  alias WandererKills.Zkb.Client, as: ZkbClient
  alias WandererKills.Core.{Error, Config}
  alias WandererKills.Observability.Telemetry

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type killmail :: map()

  @doc """
  Fetches a single killmail from zKillboard with telemetry.
  """
  @spec fetch_killmail(killmail_id(), module() | nil) :: {:ok, killmail()} | {:error, term()}
  def fetch_killmail(killmail_id, client \\ nil)

  def fetch_killmail(killmail_id, client)
      when is_integer(killmail_id) and killmail_id > 0 do
    actual_client = client || Config.zkb_client()

    Logger.debug("Fetching killmail from ZKB",
      killmail_id: killmail_id,
      operation: :fetch_killmail,
      step: :start
    )

    Telemetry.fetch_system_start(killmail_id, 1, :zkb)

    case actual_client.fetch_killmail(killmail_id) do
      {:ok, nil} ->
        Telemetry.fetch_system_error(killmail_id, :not_found, :zkb)
        {:error, Error.zkb_error(:not_found, "Killmail not found in zKillboard", false)}

      {:ok, killmail} ->
        Telemetry.fetch_system_complete(killmail_id, :success)

        Logger.debug("Successfully fetched killmail from ZKB",
          killmail_id: killmail_id,
          operation: :fetch_killmail,
          step: :success
        )

        {:ok, killmail}

      {:error, reason} ->
        Telemetry.fetch_system_error(killmail_id, reason, :zkb)

        Logger.error("Failed to fetch killmail from ZKB",
          killmail_id: killmail_id,
          operation: :fetch_killmail,
          error: reason,
          step: :error
        )

        {:error, reason}
    end
  end

  def fetch_killmail(invalid_id, _client) do
    {:error,
     Error.validation_error(:invalid_format, "Invalid killmail ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Fetches killmails for a specific system from zKillboard with telemetry.
  """
  @spec fetch_system_killmails(system_id(), pos_integer(), pos_integer(), module() | nil) ::
          {:ok, [killmail()]} | {:error, term()}
  def fetch_system_killmails(system_id, limit, since_hours, client \\ nil)

  def fetch_system_killmails(system_id, limit, since_hours, client)
      when is_integer(system_id) and system_id > 0 do
    actual_client = client || ZkbClient

    Logger.debug("Fetching system killmails from ZKB",
      system_id: system_id,
      limit: limit,
      since_hours: since_hours,
      operation: :fetch_system_killmails,
      step: :start
    )

    Telemetry.fetch_system_start(system_id, limit, :zkb)

    case actual_client.fetch_system_killmails(system_id) do
      {:ok, killmails} when is_list(killmails) ->
        Telemetry.fetch_system_success(system_id, length(killmails), :zkb)

        Logger.debug("Successfully fetched system killmails from ZKB",
          system_id: system_id,
          killmail_count: length(killmails),
          operation: :fetch_system_killmails,
          step: :success
        )

        {:ok, killmails}

      {:error, reason} ->
        Telemetry.fetch_system_error(system_id, reason, :zkb)

        Logger.error("Failed to fetch system killmails from ZKB",
          system_id: system_id,
          operation: :fetch_system_killmails,
          error: reason,
          step: :error
        )

        {:error, reason}
    end
  end

  def fetch_system_killmails(invalid_id, _limit, _since_hours, _client) do
    {:error,
     Error.validation_error(:invalid_format, "Invalid system ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Gets the kill count for a system from zKillboard with telemetry.
  """
  @spec get_system_kill_count(system_id(), module() | nil) :: {:ok, integer()} | {:error, term()}
  def get_system_kill_count(system_id, client \\ nil)

  def get_system_kill_count(system_id, client)
      when is_integer(system_id) and system_id > 0 do
    actual_client = client || ZkbClient

    Logger.debug("Fetching system kill count from ZKB",
      system_id: system_id,
      operation: :get_system_kill_count,
      step: :start
    )

    case actual_client.get_system_kill_count(system_id) do
      {:ok, count} when is_integer(count) ->
        Logger.debug("Successfully fetched system kill count from ZKB",
          system_id: system_id,
          kill_count: count,
          operation: :get_system_kill_count,
          step: :success
        )

        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to fetch system kill count from ZKB",
          system_id: system_id,
          operation: :get_system_kill_count,
          error: reason,
          step: :error
        )

        {:error, reason}
    end
  end

  def get_system_kill_count(invalid_id, _client) do
    {:error,
     Error.validation_error(:invalid_format, "Invalid system ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Fetches active systems from zKillboard with caching.
  """
  @spec fetch_active_systems(keyword()) :: {:ok, [system_id()]} | {:error, term()}
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

  defp fetch_from_cache do
    alias WandererKills.Core.Cache

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

  defp do_fetch_active_systems do
    case ZkbClient.fetch_active_systems() do
      {:ok, systems} ->
        Logger.debug("Successfully fetched active systems from ZKB",
          system_count: length(systems),
          operation: :fetch_active_systems,
          step: :success
        )

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
end
