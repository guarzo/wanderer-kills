defmodule WandererKills.Web.Api.KillfeedController do
  @moduledoc """
  HTTP API controller for killfeed polling and real-time event access.

  Integrates with WandererKills.KillmailStore to provide:
  - Batch polling for multiple events
  - Single event fetching with client offset tracking
  - Integration with existing logging and error handling patterns
  """

  require Logger
  import Plug.Conn

  alias WandererKills.KillmailStore

  @doc """
  Polls for multiple killmail events for a client.

  ## Query Parameters
  - `client_id` - Required. Unique identifier for the client
  - `systems[]` - Required. Array of system IDs to fetch events for

  ## Responses
  - 200 - JSON array of events
  - 204 - No new events (empty response)
  - 400 - Invalid parameters
  - 500 - Internal server error
  """
  def poll(conn, params) do
    with {:ok, client_id} <- validate_client_id(params),
         {:ok, system_ids} <- validate_system_ids(params),
         {:ok, events} <- KillmailStore.fetch_for_client(client_id, system_ids) do

      case events do
        [] ->
          Logger.debug("No new events for client", %{
            client_id: client_id,
            system_ids: system_ids,
            operation: :killfeed_poll,
            status: :no_content
          })

          send_resp(conn, 204, "")

        events ->
          Logger.info("Returning events for client", %{
            client_id: client_id,
            system_ids: system_ids,
            event_count: length(events),
            operation: :killfeed_poll,
            status: :success
          })

          # Transform events to API format
          api_events = Enum.map(events, fn {event_id, system_id, killmail} ->
            %{
              event_id: event_id,
              system_id: system_id,
              killmail: killmail
            }
          end)

          send_json_resp(conn, 200, %{events: api_events})
      end
    else
      {:error, :missing_client_id} ->
        send_json_resp(conn, 400, %{error: "Missing required parameter: client_id"})

      {:error, :missing_systems} ->
        send_json_resp(conn, 400, %{error: "Missing required parameter: systems"})

      {:error, :invalid_systems} ->
        send_json_resp(conn, 400, %{error: "Invalid systems parameter format"})

      {:error, reason} ->
        Logger.error("Failed to fetch events for client", %{
          client_id: Map.get(params, "client_id"),
          operation: :killfeed_poll,
          error: reason,
          status: :error
        })

        send_json_resp(conn, 500, %{error: "Internal server error"})
    end
  end

  @doc """
  Fetches the next single killmail event for a client.

  ## Query Parameters
  - `client_id` - Required. Unique identifier for the client
  - `systems[]` - Required. Array of system IDs to fetch events for

  ## Responses
  - 200 - JSON object with single event
  - 204 - No new events available
  - 400 - Invalid parameters
  - 500 - Internal server error
  """
  def next(conn, params) do
    with {:ok, client_id} <- validate_client_id(params),
         {:ok, system_ids} <- validate_system_ids(params) do

      case KillmailStore.fetch_one_event(client_id, system_ids) do
        :empty ->
          Logger.debug("No new events for client", %{
            client_id: client_id,
            system_ids: system_ids,
            operation: :killfeed_next,
            status: :no_content
          })

          send_resp(conn, 204, "")

        {:ok, {event_id, system_id, killmail}} ->
          Logger.info("Returning single event for client", %{
            client_id: client_id,
            event_id: event_id,
            system_id: system_id,
            operation: :killfeed_next,
            status: :success
          })

          send_json_resp(conn, 200, %{
            event_id: event_id,
            system_id: system_id,
            killmail: killmail
          })
      end
    else
      {:error, :missing_client_id} ->
        send_json_resp(conn, 400, %{error: "Missing required parameter: client_id"})

      {:error, :missing_systems} ->
        send_json_resp(conn, 400, %{error: "Missing required parameter: systems"})

      {:error, :invalid_systems} ->
        send_json_resp(conn, 400, %{error: "Invalid systems parameter format"})

      {:error, reason} ->
        Logger.error("Failed to fetch next event for client", %{
          client_id: Map.get(params, "client_id"),
          operation: :killfeed_next,
          error: reason,
          status: :error
        })

        send_json_resp(conn, 500, %{error: "Internal server error"})
    end
  end

  # Private helper functions

  @spec validate_client_id(map()) :: {:ok, String.t()} | {:error, :missing_client_id}
  defp validate_client_id(%{"client_id" => client_id}) when is_binary(client_id) and client_id != "" do
    {:ok, client_id}
  end

  defp validate_client_id(_params) do
    {:error, :missing_client_id}
  end

  @spec validate_system_ids(map()) :: {:ok, [integer()]} | {:error, :missing_systems | :invalid_systems}
  defp validate_system_ids(%{"systems" => systems}) when is_list(systems) do
    try do
      system_ids = Enum.map(systems, fn
        system when is_binary(system) ->
          case Integer.parse(system) do
            {id, ""} when id > 0 -> id
            _ -> throw(:invalid_system_id)
          end
        system when is_integer(system) and system > 0 ->
          system
        _ ->
          throw(:invalid_system_id)
      end)

      {:ok, system_ids}
    catch
      :invalid_system_id -> {:error, :invalid_systems}
    end
  end

  defp validate_system_ids(_params) do
    {:error, :missing_systems}
  end

  @spec send_json_resp(Plug.Conn.t(), integer(), term()) :: Plug.Conn.t()
  defp send_json_resp(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
