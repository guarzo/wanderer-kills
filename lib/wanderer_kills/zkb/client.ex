defmodule WandererKills.Zkb.Client do
  @moduledoc """
  API client for zKillboard.
  """

  require Logger
  alias WandererKills.Http.Client, as: HttpClient

  @user_agent "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"
  @base_url Application.compile_env(:wanderer_kills, [:zkb, :base_url])

  @doc """
  Fetches a killmail from zKillboard.
  Returns {:ok, killmail} or {:error, reason}.
  """
  def fetch_killmail(killmail_id) do
    url = "#{base_url()}/killID/#{killmail_id}/"
    params = build_query_params(no_items: true)

    case HttpClient.get_with_rate_limit(url,
           params: params,
           headers: [{"user-agent", @user_agent}]
         ) do
      {:ok, response} -> parse_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches killmails for a system from zKillboard.
  Returns {:ok, [killmail]} or {:error, reason}.
  """
  def fetch_system_killmails(system_id) do
    url = "#{base_url()}/systemID/#{system_id}/"
    params = build_query_params(no_items: true)

    case HttpClient.get_with_rate_limit(url,
           params: params,
           headers: [{"user-agent", @user_agent}]
         ) do
      {:ok, response} -> parse_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets killmails for a corporation from zKillboard.
  """
  def get_corporation_killmails(corporation_id) do
    url = "#{base_url()}/corporationID/#{corporation_id}/"
    params = build_query_params(no_items: true)

    case HttpClient.get_with_rate_limit(url,
           params: params,
           headers: [{"user-agent", @user_agent}]
         ) do
      {:ok, response} -> parse_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets killmails for an alliance from zKillboard.
  """
  def get_alliance_killmails(alliance_id) do
    url = "#{base_url()}/allianceID/#{alliance_id}/"
    params = build_query_params(no_items: true)

    case HttpClient.get_with_rate_limit(url,
           params: params,
           headers: [{"user-agent", @user_agent}]
         ) do
      {:ok, response} -> parse_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets killmails for a character from zKillboard.
  """
  def get_character_killmails(character_id) do
    url = "#{base_url()}/characterID/#{character_id}/"
    params = build_query_params(no_items: true)

    case HttpClient.get_with_rate_limit(url,
           params: params,
           headers: [{"user-agent", @user_agent}]
         ) do
      {:ok, response} -> parse_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches killmails for a system from ESI.
  Returns {:ok, [killmail]} or {:error, reason}.
  """
  def fetch_system_killmails_esi(system_id) do
    url = "#{base_url()}/systemID/#{system_id}/"

    case HttpClient.get_with_rate_limit(url, headers: [{"user-agent", @user_agent}]) do
      {:ok, response} -> parse_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Enriches a killmail with additional information.
  Returns {:ok, enriched_killmail} or {:error, reason}.
  """
  def enrich_killmail(killmail) do
    with {:ok, victim} <- get_victim_info(killmail),
         {:ok, attackers} <- get_attackers_info(killmail),
         {:ok, items} <- get_items_info(killmail) do
      enriched =
        Map.merge(killmail, %{
          "victim" => victim,
          "attackers" => attackers,
          "items" => items
        })

      {:ok, enriched}
    end
  end

  @doc """
  Gets the kill count for a system.
  Returns {:ok, count} or {:error, reason}.
  """
  def get_system_kill_count(system_id) when is_integer(system_id) do
    url = "#{base_url()}/systemID/#{system_id}/"

    case HttpClient.get_with_rate_limit(url, headers: [{"user-agent", @user_agent}]) do
      {:ok, response} ->
        case parse_response(response) do
          {:ok, data} when is_list(data) ->
            {:ok, length(data)}

          {:ok, _} ->
            {:error, :unexpected_response}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_system_kill_count(_system_id) do
    {:error, :invalid_system_id}
  end

  @doc """
  Builds query parameters for zKillboard API requests.
  Available options:
  - no_items: boolean() - Whether to exclude items from the response
  - startTime: DateTime.t() - Filter kills after this time
  - endTime: DateTime.t() - Filter kills before this time
  - limit: pos_integer() - Maximum number of kills to return
  """
  @spec build_query_params(keyword()) :: keyword()
  def build_query_params(opts \\ []) do
    opts
    |> Enum.map(fn
      {:no_items, true} -> {:no_items, "true"}
      {:startTime, %DateTime{} = time} -> {:startTime, DateTime.to_iso8601(time)}
      {:endTime, %DateTime{} = time} -> {:endTime, DateTime.to_iso8601(time)}
      {:limit, limit} when is_integer(limit) and limit > 0 -> {:limit, limit}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Helper functions for enriching killmails
  defp get_victim_info(killmail) do
    victim = Map.get(killmail, "victim", %{})
    {:ok, victim}
  end

  defp get_attackers_info(killmail) do
    attackers = Map.get(killmail, "attackers", [])
    {:ok, attackers}
  end

  defp get_items_info(killmail) do
    items = Map.get(killmail, "items", [])
    {:ok, items}
  end

  @doc """
  Fetches active systems from zKillboard.
  Returns {:ok, [system_id]} or {:error, reason}.
  """
  def fetch_active_systems do
    url = "#{base_url()}/systems/"

    case HttpClient.get_with_rate_limit(url, headers: [{"user-agent", @user_agent}]) do
      {:ok, response} ->
        case parse_response(response) do
          {:ok, systems} when is_list(systems) ->
            {:ok, systems}

          {:ok, _} ->
            {:error, :unexpected_response}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the base URL for zKillboard API calls.
  """
  def base_url do
    @base_url
  end

  defp parse_response(%{status: 200, body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response(%{status: 200, body: body}) do
    {:ok, body}
  end

  defp parse_response(%{status: status}) do
    {:error, "Unexpected status code: #{status}"}
  end
end
