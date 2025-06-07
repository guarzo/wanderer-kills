defmodule WandererKillsWeb.Api.KillfeedController do
  @moduledoc """
  Controller for handling killfeed polling and real-time event access.

  Integrates with WandererKills.Killmails.Store to provide:
  - Batch polling for multiple events
  - Single event fetching with client offset tracking
  - Integration with existing logging and error handling patterns
  """

  require Logger
  import Plug.Conn
  import WandererKillsWeb.Api.Helpers, only: [send_json_resp: 3]

  alias WandererKills.Killmails.Store
  alias WandererKills.Core.Constants

  # Client ID validation
  defp validate_client_id(client_id) when is_binary(client_id) do
    cond do
      byte_size(client_id) == 0 ->
        {:error, :client_id_empty}

      byte_size(client_id) > 100 ->
        {:error, :client_id_too_long}

      not String.match?(client_id, ~r/^[a-zA-Z0-9_-]+$/) ->
        {:error, :client_id_invalid_chars}

      true ->
        {:ok, client_id}
    end
  end

  defp validate_client_id(_), do: {:error, :client_id_invalid_type}

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
  defp handle_error(conn, :client_id_empty) do
    send_json_resp(conn, 400, %{error: "Client ID cannot be empty"})
  end

  defp handle_error(conn, :client_id_too_long) do
    send_json_resp(conn, 400, %{error: "Client ID exceeds maximum length"})
  end

  defp handle_error(conn, :client_id_invalid_chars) do
    send_json_resp(conn, 400, %{error: "Client ID contains invalid characters"})
  end

  defp handle_error(conn, :client_id_invalid_type) do
    send_json_resp(conn, 400, %{error: "Client ID must be a string"})
  end

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

  # Event transformation
  defp transform_event({event_id, system_id, killmail}) do
    %{
      event_id: event_id,
      system_id: system_id,
      killmail: killmail
    }
  end

  # Controller actions
  def poll(conn, %{"client_id" => client_id, "systems" => systems}) do
    with {:ok, valid_client_id} <- validate_client_id(client_id),
         {:ok, valid_systems} <- validate_system_ids(systems),
         {:ok, events} <- Store.fetch_for_client(valid_client_id, valid_systems) do
      if Enum.empty?(events) do
        send_resp(conn, 204, "")
      else
        send_json_resp(conn, 200, %{
          events: Enum.map(events, &transform_event/1)
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

  def next(conn, %{"client_id" => client_id, "systems" => systems}) do
    with {:ok, valid_client_id} <- validate_client_id(client_id),
         {:ok, valid_systems} <- validate_system_ids(systems) do
      case Store.fetch_one_event(valid_client_id, valid_systems) do
        {:ok, event} ->
          send_json_resp(conn, 200, transform_event(event))

        :empty ->
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
