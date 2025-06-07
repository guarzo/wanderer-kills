defmodule WandererKillsWeb.Api do
  @moduledoc """
  HTTP API for the Wanderer Kills service.
  """

  use Plug.Router
  require Logger
  import Plug.Conn
  import WandererKillsWeb.Api.Helpers, only: [send_json_resp: 3]

  alias WandererKills.Observability.Monitoring
  alias WandererKills.Cache.Helper
  alias WandererKillsWeb.Plugs.RequestId

  plug(Plug.Logger, log: :info)
  plug(RequestId)
  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(:dispatch)

  # Health check endpoint
  get "/ping" do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "pong")
  end

  # Health endpoint with cache status
  get "/health" do
    case Monitoring.check_health() do
      {:ok, health_status} ->
        status_code = if health_status.healthy, do: 200, else: 503
        send_json_resp(conn, status_code, health_status)

      {:error, reason} ->
        send_json_resp(conn, 503, %{error: "Health check failed", reason: inspect(reason)})
    end
  end

  # Metrics endpoint
  get "/metrics" do
    case Monitoring.get_metrics() do
      {:ok, metrics} ->
        send_json_resp(conn, 200, metrics)

      {:error, reason} ->
        send_json_resp(conn, 500, %{error: "Metrics collection failed", reason: inspect(reason)})
    end
  end

  # Get a killmail by ID
  get "/killmail/:id" do
    case validate_killmail_id(id) do
      {:ok, killmail_id} ->
        case fetch_and_cache_killmail(killmail_id) do
          {:error, :not_found} ->
            handle_killmail_response({:error, :not_found}, killmail_id, conn)

          {:error, reason} ->
            handle_killmail_response({:error, reason}, killmail_id, conn)

          {:ok, killmail} ->
            handle_killmail_response({:ok, killmail}, killmail_id, conn)
        end

      {:error, :invalid_format} ->
        send_json_resp(conn, 400, %{error: "Invalid killmail ID"})
    end
  end

  # Get killmails for a system
  get "/system_killmails/:system_id" do
    case validate_system_id(system_id) do
      {:ok, id} ->
        case fetch_killmails_for_system(id) do
          {:ok, killmails} ->
            handle_system_killmails_response({:ok, killmails}, id, conn)

          {:error, reason} ->
            handle_system_killmails_response({:error, reason}, id, conn)
        end

      {:error, :invalid_format} ->
        send_json_resp(conn, 400, %{error: "Invalid system ID"})
    end
  end

  # Get kill count for a system
  get "/system_kill_count/:system_id" do
    case validate_system_id(system_id) do
      {:ok, id} ->
        case Helper.system_get_kill_count(id) do
          {:ok, count} when is_integer(count) ->
            Logger.info("Successfully fetched kill count for system", %{
              system_id: id,
              kill_count: count,
              status: :success
            })

            send_json_resp(conn, 200, %{count: count})

          {:error, reason} ->
            Logger.error("Failed to fetch kill count for system", %{
              system_id: id,
              error: reason,
              status: :error
            })

            send_json_resp(conn, 500, %{error: "Internal server error"})
        end

      {:error, :invalid_format} ->
        send_json_resp(conn, 400, %{error: "Invalid system ID"})
    end
  end

  # Get killmails for a system (alternative route)
  get "/system/:id/killmails" do
    case validate_system_id(id) do
      {:ok, system_id} ->
        case fetch_killmails_for_system(system_id) do
          {:ok, killmails} ->
            Logger.info("Successfully fetched killmails for system", %{
              system_id: system_id,
              killmail_count: length(killmails),
              status: :success,
              route: :alternative
            })

            send_json_resp(conn, 200, %{killmails: killmails})

          {:error, reason} ->
            Logger.error("Failed to fetch killmails for system", %{
              system_id: system_id,
              error: reason,
              status: :error,
              route: :alternative
            })

            send_json_resp(conn, 500, %{error: "Internal server error"})
        end

      {:error, :invalid_format} ->
        send_json_resp(conn, 400, %{error: "Invalid system ID"})
    end
  end

  # Legacy endpoint that redirects to /system_killmails/:system_id
  get "/kills_for_system/:system_id" do
    case validate_system_id(system_id) do
      {:ok, id} ->
        conn
        |> put_status(302)
        |> put_resp_header("location", "/system_killmails/#{id}")
        |> send_resp(302, "")

      {:error, :invalid_format} ->
        send_json_resp(conn, 400, %{error: "Invalid system ID"})
    end
  end

  # Killfeed endpoints
  get "/api/killfeed" do
    WandererKillsWeb.Api.KillfeedController.poll(conn, conn.query_params)
  end

  get "/api/killfeed/next" do
    WandererKillsWeb.Api.KillfeedController.next(conn, conn.query_params)
  end

  # Catch-all route
  match _ do
    Logger.warning("Invalid request path", %{
      path: conn.request_path,
      method: conn.method,
      error_type: :not_found
    })

    send_json_resp(conn, 404, %{error: "Not found"})
  end

  @spec handle_killmail_response({:ok, map()} | {:error, term()}, integer(), Plug.Conn.t()) ::
          Plug.Conn.t()
  defp handle_killmail_response({:ok, killmail}, killmail_id, conn) do
    Logger.info("Successfully fetched killmail",
      killmail_id: killmail_id,
      status: :success
    )

    send_json_resp(conn, 200, killmail)
  end

  defp handle_killmail_response({:error, :not_found}, killmail_id, conn) do
    Logger.info("Killmail not found",
      killmail_id: killmail_id,
      status: :not_found
    )

    send_json_resp(conn, 404, %{error: "Killmail not found"})
  end

  defp handle_killmail_response(
         {:error, %WandererKills.Infrastructure.Error{domain: :zkb, type: :not_found}},
         killmail_id,
         conn
       ) do
    Logger.info("Killmail not found",
      killmail_id: killmail_id,
      status: :not_found
    )

    send_json_resp(conn, 404, %{error: "Killmail not found"})
  end

  defp handle_killmail_response({:error, reason}, killmail_id, conn) do
    Logger.error("Failed to fetch killmail",
      killmail_id: killmail_id,
      error: reason,
      status: :error
    )

    send_json_resp(conn, 500, %{error: "Internal server error"})
  end

  @spec validate_killmail_id(String.t()) :: {:ok, integer()} | {:error, :invalid_format}
  defp validate_killmail_id(id_str) do
    case Integer.parse(id_str) do
      {id, ""} when id > 0 ->
        {:ok, id}

      _ ->
        Logger.warning("Invalid killmail ID format",
          provided_id: id_str,
          status: :invalid_format
        )

        {:error, :invalid_format}
    end
  end

  @spec handle_system_killmails_response(
          {:ok, list()} | {:error, term()},
          integer(),
          Plug.Conn.t()
        ) :: Plug.Conn.t()
  defp handle_system_killmails_response({:ok, killmails}, system_id, conn) do
    Logger.info("Successfully fetched killmails for system",
      system_id: system_id,
      killmail_count: length(killmails),
      status: :success
    )

    send_json_resp(conn, 200, killmails)
  end

  defp handle_system_killmails_response({:error, reason}, system_id, conn) do
    Logger.error("Failed to fetch killmails for system",
      system_id: system_id,
      error: reason,
      status: :error
    )

    send_json_resp(conn, 500, %{error: "Internal server error"})
  end

  @spec validate_system_id(String.t()) :: {:ok, integer()} | {:error, :invalid_format}
  defp validate_system_id(id_str) do
    case Integer.parse(id_str) do
      {id, ""} when id > 0 ->
        {:ok, id}

      _ ->
        Logger.warning("Invalid system ID format",
          provided_id: id_str,
          status: :invalid_format
        )

        {:error, :invalid_format}
    end
  end

  # Helper functions to replace Fetching.Coordinator functionality

  @spec fetch_and_cache_killmail(integer()) :: {:ok, map()} | {:error, term()}
  defp fetch_and_cache_killmail(killmail_id) do
    alias WandererKills.Killmails.ZkbClient, as: ZKB
    alias WandererKills.Killmails.Coordinator
    alias WandererKills.Cache.Helper

    with {:ok, raw_killmail} <- ZKB.fetch_killmail(killmail_id),
         {:ok, processed_killmail} <- Coordinator.process_single_killmail(raw_killmail),
         :ok <- Helper.killmail_put(killmail_id, processed_killmail) do
      {:ok, processed_killmail}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_killmails_for_system(integer()) :: {:ok, list()} | {:error, term()}
  defp fetch_killmails_for_system(system_id) do
    alias WandererKills.Killmails.ZkbClient, as: ZKB
    alias WandererKills.Killmails.Coordinator
    alias WandererKills.Cache.Helper

    # Check cache first
    case Helper.system_recently_fetched?(system_id) do
      {:ok, true} ->
        # Cache is fresh, get cached data
        case Helper.system_get_killmails(system_id) do
          {:ok, killmail_ids} -> {:ok, killmail_ids}
          {:error, _reason} -> fetch_remote_killmails(system_id)
        end

      {:ok, false} ->
        # Cache is stale, fetch from remote
        fetch_remote_killmails(system_id)

      {:error, _reason} ->
        # Cache check failed, fetch from remote
        fetch_remote_killmails(system_id)
    end
  end

  @spec fetch_remote_killmails(integer()) :: {:ok, list()} | {:error, term()}
  defp fetch_remote_killmails(system_id) do
    alias WandererKills.Killmails.ZkbClient, as: ZKB
    alias WandererKills.Killmails.Coordinator

    # Default limit
    limit = 5
    # Default since hours
    since_hours = 24

    with {:ok, raw_killmails} <- ZKB.fetch_system_killmails(system_id, limit, since_hours),
         {:ok, processed_killmails} <-
           Coordinator.process_killmails(raw_killmails, system_id, since_hours),
         :ok <-
           WandererKills.Cache.Helper.cache_killmails_for_system(
             system_id,
             processed_killmails
           ) do
      {:ok, processed_killmails}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
