defmodule WandererKills.External.ZKB.Fetcher do
  @moduledoc """
  Fetches killmails from zKillboard sources and stores them.

  This module handles on-demand killmail fetching from zKillboard API,
  as opposed to the streaming RedisQ operations.
  """

  alias WandererKills.Zkb.Client, as: ZkbClient
  alias WandererKills.Killmails.Store

  @doc """
  Fetches a killmail by ID and stores it.
  """
  def fetch_killmail(killmail_id, client \\ nil) do
    actual_client = get_client(client)

    case actual_client.fetch_killmail(killmail_id) do
      {:ok, killmail} when is_map(killmail) ->
        Store.store_killmail(killmail)
        {:ok, killmail}

      {:ok, nil} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Fetches all killmails for a system and stores them.
  """
  def fetch_system_killmails(system_id, client \\ nil) do
    actual_client = get_client(client)

    case actual_client.fetch_system_killmails(system_id) do
      {:ok, killmails} when is_list(killmails) ->
        Enum.each(killmails, &process_killmail(&1, system_id))
        {:ok, killmails}

      error ->
        error
    end
  end

  defp get_client(client) do
    client || ZkbClient
  end

  defp process_killmail(killmail, system_id) do
    if is_map(killmail) do
      Store.store_killmail(killmail)
      store_system_killmail_if_valid(killmail, system_id)
    end
  end

  defp store_system_killmail_if_valid(killmail, system_id) do
    killmail_id = killmail["killID"] || killmail["killmail_id"]

    if killmail_id do
      Store.add_system_killmail(system_id, killmail_id)
    end
  end
end
