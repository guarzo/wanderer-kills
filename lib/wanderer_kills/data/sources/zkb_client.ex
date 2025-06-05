defmodule WandererKills.Data.Sources.ZkbClient do
  @moduledoc """
  Implementation of ZKB API client.
  """

  @behaviour WandererKills.Data.Sources.ZkbClientBehaviour

  alias WandererKills.Http.Client
  alias WandererKills.Config

  @impl true
  def fetch_killmail(killmail_id) do
    base_url = Config.zkb_base_url()

    case Client.get_with_rate_limit("#{base_url}/killID/#{killmail_id}/") do
      {:ok, %Req.Response{body: body}} -> {:ok, body}
      other -> other
    end
  end

  @impl true
  def fetch_system_killmails(system_id) do
    base_url = Config.zkb_base_url()

    case Client.get_with_rate_limit("#{base_url}/systemID/#{system_id}/") do
      {:ok, %Req.Response{body: body}} -> {:ok, body}
      other -> other
    end
  end

  @impl true
  def fetch_system_kill_count(system_id) do
    base_url = Config.zkb_base_url()

    case Client.get_with_rate_limit("#{base_url}/systemID/#{system_id}/count/") do
      {:ok, %Req.Response{body: body}} -> {:ok, body}
      other -> other
    end
  end

  @impl true
  def fetch_system_killmails_esi(system_id) do
    base_url = Config.zkb_base_url()

    case Client.get_with_rate_limit("#{base_url}/systemID/#{system_id}/esi/") do
      {:ok, %Req.Response{body: body}} -> {:ok, body}
      other -> other
    end
  end

  @impl true
  def enrich_killmail(killmail) do
    {:ok, killmail}
  end

  @impl true
  def get_system_kill_count(system_id) do
    fetch_system_kill_count(system_id)
  end
end
