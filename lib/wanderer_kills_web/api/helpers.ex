defmodule WandererKillsWeb.Api.Helpers do
  @moduledoc """
  Helper functions for API controllers.
  """

  import Plug.Conn

  @doc """
  Parses an integer parameter from the request.
  Returns {:ok, integer} or {:error, :invalid_id}.
  """
  @spec parse_integer_param(Plug.Conn.t(), String.t()) :: {:ok, integer()} | {:error, :invalid_id}
  def parse_integer_param(conn, param_name) do
    case Map.get(conn.params, param_name) do
      nil ->
        {:error, :invalid_id}

      "" ->
        {:error, :invalid_id}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 ->
            {:ok, int}

          {int, ""} when int <= 0 ->
            # Allow negative numbers for some use cases
            {:ok, int}

          _ ->
            {:error, :invalid_id}
        end

      value when is_integer(value) ->
        {:ok, value}

      _ ->
        {:error, :invalid_id}
    end
  end

  @doc """
  Sends a JSON response.
  """
  @spec send_json_resp(Plug.Conn.t(), integer(), term()) :: Plug.Conn.t()
  def send_json_resp(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
