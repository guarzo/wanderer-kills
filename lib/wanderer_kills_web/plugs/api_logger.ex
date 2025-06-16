defmodule WandererKillsWeb.Plugs.ApiLogger do
  @moduledoc """
  Custom API logger plug for structured request/response logging.

  Provides more detailed logging than the default Plug.Logger with
  structured metadata for better observability.
  """

  require Logger
  alias WandererKillsWeb.Shared.Parsers

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    start_time = System.monotonic_time()

    # Log the incoming request
    Logger.info("API request started",
      method: conn.method,
      path: conn.request_path,
      query_string: conn.query_string,
      user_agent: get_user_agent(conn),
      remote_ip: get_remote_ip(conn)
    )

    # Register a callback to log the response
    Plug.Conn.register_before_send(conn, fn conn ->
      end_time = System.monotonic_time()
      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      Logger.info("API request completed",
        method: conn.method,
        path: conn.request_path,
        status: conn.status,
        duration_ms: duration_ms,
        response_size: get_response_size(conn)
      )

      conn
    end)
  end

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [user_agent] -> user_agent
      _ -> "unknown"
    end
  end

  defp get_remote_ip(conn) do
    :inet.ntoa(conn.remote_ip) |> to_string()
  end

  defp get_response_size(conn) do
    case Plug.Conn.get_resp_header(conn, "content-length") do
      [size] -> Parsers.parse_int(size, 0)
      _ -> 0
    end
  end
end
