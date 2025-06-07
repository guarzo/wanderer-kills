defmodule WandererKills.Fetching.ZkbService do
  @moduledoc """
  Pure ZKB API interaction service.

  This module handles all direct interactions with zKillboard API,
  including fetching individual killmails, system killmails, and kill counts.
  It focuses solely on API communication without caching or processing logic.
  """

  require Logger
  alias WandererKills.Zkb.Client, as: ZkbClient
  alias WandererKills.Core.{Error, Config}
  alias WandererKills.Observability.Telemetry

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type killmail :: map()

  @doc """
  Fetches a single killmail from zKillboard.

  ## Parameters
  - `killmail_id` - The ID of the killmail to fetch
  - `client` - Optional ZKB client module (for testing)

  ## Returns
  - `{:ok, killmail}` - On successful fetch
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, killmail} = ZkbService.fetch_killmail(12345)
  {:error, reason} = ZkbService.fetch_killmail(99999)
  ```
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
  Fetches killmails for a specific system from zKillboard.

  ## Parameters
  - `system_id` - The system ID to fetch killmails for
  - `limit` - Maximum number of killmails to fetch (used for telemetry)
  - `since_hours` - Only fetch killmails newer than this (used for telemetry)
  - `client` - Optional ZKB client module (for testing)

  ## Returns
  - `{:ok, [killmail]}` - On successful fetch
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, killmails} = ZkbService.fetch_system_killmails(30000142, 10, 24)
  {:error, reason} = ZkbService.fetch_system_killmails(99999, 5, 24)
  ```
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

    # ZKB client doesn't accept limit or since_hours parameters directly
    # These parameters are used for telemetry and will be handled in the processor
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
  Gets the kill count for a system from zKillboard stats.

  ## Parameters
  - `system_id` - The system ID (integer)
  - `client` - Optional ZKB client module (for testing)

  ## Returns
  - `{:ok, count}` - On success
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, 15} = ZkbService.get_system_kill_count(30000142)
  {:error, reason} = ZkbService.get_system_kill_count(99999)
  ```
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
  Handles ZKB API response standardization.

  This function can be used to normalize responses from different ZKB endpoints
  or handle common response patterns.
  """
  @spec handle_zkb_response(term()) :: {:ok, term()} | {:error, term()}
  def handle_zkb_response({:ok, data}), do: {:ok, data}
  def handle_zkb_response({:error, reason}), do: {:error, reason}

  def handle_zkb_response(other) do
    Logger.warning("Unexpected ZKB response format", response: inspect(other))
    {:error, Error.zkb_error(:unexpected_response, "Unexpected response format from ZKB")}
  end
end
