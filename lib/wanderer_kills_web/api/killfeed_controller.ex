defmodule WandererKillsWeb.Api.KillfeedController do
  @moduledoc """
  Controller for handling killfeed access.

  Provides basic killmail retrieval by system using the simplified KillStore API.
  """

  require Logger
  import Plug.Conn
  import WandererKillsWeb.Api.Helpers, only: [send_json_resp: 3]

  alias WandererKills.Killmails.Store
  alias WandererKills.Core.Constants

  # System ID validation
  defp validate_system_ids(system_ids) when is_list(system_ids) do
    Enum.reduce_while(system_ids, {:ok, []}, fn system_id, {:ok, acc} ->
      case validate_system_id(system_id) do
        {:ok, valid_id} -> {:cont, {:ok, [valid_id | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, valid_ids} -> {:ok, Enum.reverse(valid_ids)}
      error -> error
    end
  end

  defp validate_system_ids(_), do: {:error, :systems_invalid_type}

  defp validate_system_id(system_id) when is_integer(system_id) do
    if system_id >= 30_000_000 and system_id <= Constants.validation(:max_system_id) do
      {:ok, system_id}
    else
      {:error, :system_id_out_of_range}
    end
  end

  defp validate_system_id(_), do: {:error, :system_id_invalid_type}

  # Error response helpers
  defp handle_error(conn, :systems_invalid_type) do
    send_json_resp(conn, 400, %{error: "Systems must be an array"})
  end

  defp handle_error(conn, :system_id_invalid_type) do
    send_json_resp(conn, 400, %{error: "System ID must be an integer"})
  end

  defp handle_error(conn, :system_id_out_of_range) do
    send_json_resp(conn, 400, %{error: "System ID is out of valid range"})
  end

  defp handle_error(conn, :internal_error) do
    send_json_resp(conn, 500, %{error: "Internal server error"})
  end

  # Controller actions
  def poll(conn, %{"systems" => systems}) do
    with {:ok, valid_systems} <- validate_system_ids(systems) do
      killmails =
        valid_systems
        |> Enum.flat_map(&Store.list_by_system/1)
        # Limit to prevent large responses
        |> Enum.take(100)

      if Enum.empty?(killmails) do
        send_resp(conn, 204, "")
      else
        send_json_resp(conn, 200, %{
          killmails: killmails
        })
      end
    else
      {:error, reason} ->
        handle_error(conn, reason)
    end
  end

  def poll(conn, _params) do
    send_json_resp(conn, 400, %{error: "Missing required parameters"})
  end

  def next(conn, %{"systems" => systems}) do
    with {:ok, valid_systems} <- validate_system_ids(systems) do
      case valid_systems
           |> Enum.flat_map(&Store.list_by_system/1)
           |> Enum.take(1) do
        [killmail] ->
          send_json_resp(conn, 200, killmail)

        [] ->
          send_resp(conn, 204, "")
      end
    else
      {:error, reason} ->
        handle_error(conn, reason)
    end
  end

  def next(conn, _params) do
    send_json_resp(conn, 400, %{error: "Missing required parameters"})
  end
end
