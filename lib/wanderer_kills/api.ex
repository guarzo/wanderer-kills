defmodule WandererZkbService.Api do
  @moduledoc """
  HTTP interface for ZKB functionality.  
  Exposes the same high-level routes as the internal `Provider.Api`:

    • GET  /ping
    • GET  /killmail/:id
    • GET  /system_killmails/:system_id
    • GET  /kills_for_system/:system_id
    • GET  /kill_count/:system_id

  All routes return JSON (except /ping, which is a plain “pong”).
  """

  use Plug.Router
  require Logger

  alias WandererZkbService.Provider.Api, as: ZkbProvider

  plug :match
  plug :dispatch

  @doc "Simple health check."
  get "/ping" do
    send_resp(conn, 200, "pong")
  end

  @doc """
  GET /killmail/:id
  Fetch a single killmail by its ID via `ZkbProvider.get_killmail/1`.
  Returns `{"status": "ok", "killmail": <map>}` or `{"status": "error", "reason": <term>}`.
  """
  get "/killmail/:id" do
    with {id, ""} <- Integer.parse(id),
         {:ok, killmail} <- ZkbProvider.get_killmail(id) do
      resp = %{status: "ok", killmail: killmail}
      send_json(conn, 200, resp)
    else
      :error ->
        send_json(conn, 400, %{status: "error", reason: "invalid id"})
      {:error, reason} ->
        send_json(conn, 500, %{status: "error", reason: inspect(reason)})
    end
  end

  @doc """
  GET /system_killmails/:system_id
  Fetch all killmails for a given system via `ZkbProvider.get_system_killmails/1`.
  Returns `{"status":"ok","killmails":[…]}` or `{"status":"error","reason":…}`.
  """
  get "/system_killmails/:system_id" do
    with {system_id, ""} <- Integer.parse(system_id),
         {:ok, killmails} <- ZkbProvider.get_system_killmails(system_id) do
      resp = %{status: "ok", killmails: killmails}
      send_json(conn, 200, resp)
    else
      :error ->
        send_json(conn, 400, %{status: "error", reason: "invalid system_id"})
      {:error, reason} ->
        send_json(conn, 500, %{status: "error", reason: inspect(reason)})
    end
  end

  @doc """
  GET /kills_for_system/:system_id
  Alias for `/system_killmails/:system_id` (backwards compatibility).
  """
  get "/kills_for_system/:system_id" do
    # Simply forward to the other route’s logic:
    conn
    |> put_req_header("x-forwarded-for-kills_for_system", "true")
    |> Phoenix.Controller.redirect(to: "/system_killmails/" <> system_id)
  end

  @doc """
  GET /kill_count/:system_id
  Retrieves the cached kill count for a system (or computes & caches it) via
  `ZkbProvider.get_kill_count/1`. Returns `{"status":"ok","count":<integer>}` or
  `{"status":"error","reason":…}`.
  """
  get "/kill_count/:system_id" do
    with {system_id, ""} <- Integer.parse(system_id),
         {:ok, count} <- ZkbProvider.get_kill_count(system_id) do
      send_json(conn, 200, %{status: "ok", count: count})
    else
      :error ->
        send_json(conn, 400, %{status: "error", reason: "invalid system_id"})
      {:error, reason} ->
        send_json(conn, 500, %{status: "error", reason: inspect(reason)})
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end

  # Helper to set JSON content-type and encode the body
  defp send_json(conn, status, body_map) do
    json = Jason.encode!(body_map)
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, json)
  end
end
