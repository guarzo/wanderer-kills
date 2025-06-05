defmodule WandererKills.Fetcher.KillmailFetcher do
  @moduledoc """
  Fetches killmails from various sources and stores them.
  """

  alias WandererKills.Data.Sources.ZkbClient
  alias WandererKills.KillmailStore

  @doc """
  Fetches a killmail by ID and stores it.
  """
  def fetch_killmail(killmail_id, client \\ nil) do
    actual_client =
      client || Application.get_env(:wanderer_kills, :data_sources_zkb_client, ZkbClient)

    case actual_client.fetch_killmail(killmail_id) do
      {:ok, killmail} when is_map(killmail) ->
        KillmailStore.store_killmail(killmail)
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
    actual_client =
      client || Application.get_env(:wanderer_kills, :data_sources_zkb_client, ZkbClient)

    case actual_client.fetch_system_killmails(system_id) do
      {:ok, killmails} when is_list(killmails) ->
        Enum.each(killmails, fn killmail ->
          if is_map(killmail) do
            KillmailStore.store_killmail(killmail)
            killmail_id = killmail["killID"] || killmail["killmail_id"]

            if killmail_id do
              KillmailStore.add_system_killmail(system_id, killmail_id)
            end
          end
        end)

        {:ok, killmails}

      error ->
        error
    end
  end
end
