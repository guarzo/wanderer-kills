defmodule WandererKillsWeb.HealthController do
  @moduledoc """
  Health check and monitoring endpoints.

  Provides simple health checks, detailed status information,
  and metrics for monitoring systems.
  """

  use WandererKillsWeb, :controller

  alias WandererKills.Core.Observability.{Monitoring, Status}

  @doc """
  Simple ping endpoint for basic health checks.
  """
  @spec ping(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ping(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "pong")
  end

  @doc """
  Detailed health check with component status.
  """
  @spec health(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def health(conn, _params) do
    case Monitoring.check_health() do
      {:ok, health_status} ->
        status_code = if health_status.healthy, do: 200, else: 503
        response = Map.put(health_status, :timestamp, DateTime.utc_now() |> DateTime.to_iso8601())

        conn
        |> put_status(status_code)
        |> json(response)

      {:error, reason} ->
        response = %{
          error: "Health check failed",
          reason: inspect(reason),
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        conn
        |> put_status(503)
        |> json(response)
    end
  end

  @doc """
  Status endpoint with detailed service information.
  """
  @spec status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def status(conn, _params) do
    response = Status.get_service_status()
    json(conn, response)
  end

  @doc """
  Metrics endpoint for monitoring systems.
  """
  @spec metrics(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def metrics(conn, _params) do
    case Monitoring.get_metrics() do
      {:ok, metrics} ->
        json(conn, metrics)

      {:error, reason} ->
        response = %{
          error: "Metrics collection failed",
          reason: inspect(reason)
        }

        conn
        |> put_status(500)
        |> json(response)
    end
  end
end
