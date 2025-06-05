defmodule WandererKillsWeb.Api.Helpers do
  @moduledoc """
  Helper functions for API routes and responses.
  """

  @doc """
  Parses an integer parameter from the connection params.
  Returns {:ok, integer} or {:error, :invalid_id}.
  """
  def parse_integer_param(conn, key) do
    case conn.params[key] do
      nil ->
        {:error, :invalid_id}

      param ->
        case Integer.parse(param) do
          {num, ""} -> {:ok, num}
          _ -> {:error, :invalid_id}
        end
    end
  end

  @doc """
  Sends a JSON response with the given status and data.
  """
  def send_json_resp(conn, status, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(data))
  end
end
