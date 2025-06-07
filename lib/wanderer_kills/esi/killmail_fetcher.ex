defmodule WandererKills.ESI.KillmailFetcher do
  @moduledoc """
  ESI Killmail data fetcher.

  This module handles fetching killmail information from the EVE ESI API,
  using killmail ID and hash combinations.
  """

  require Logger
  alias WandererKills.Core.{Config, Error, Cache}
  alias WandererKills.Core.Behaviours.{DataFetcher}

  @behaviour DataFetcher

  @doc """
  Fetches a killmail from ESI using killmail ID and hash.
  """
  def get_killmail(killmail_id, killmail_hash)
      when is_integer(killmail_id) and is_binary(killmail_hash) do
    cache_key = {:killmail, killmail_id, killmail_hash}

    case Cache.get(:esi_cache, cache_key) do
      {:ok, killmail} ->
        {:ok, killmail}

      {:error, _} ->
        fetch_and_cache_killmail(killmail_id, killmail_hash, cache_key)
    end
  end

  @doc """
  Fetches multiple killmails concurrently.
  """
  def get_killmails_batch(killmail_specs) when is_list(killmail_specs) do
    killmail_specs
    |> Task.async_stream(
      fn {killmail_id, killmail_hash} ->
        get_killmail(killmail_id, killmail_hash)
      end,
      max_concurrency: Config.batch_concurrency(:esi),
      timeout: Config.request_timeout(:esi)
    )
    |> Enum.to_list()
    |> Enum.map(fn
      {:ok, result} ->
        result

      {:exit, reason} ->
        {:error, Error.esi_error(:timeout, "Killmail fetch timeout", %{reason: reason})}
    end)
  end

  # DataFetcher behaviour implementations
  @impl DataFetcher
  def fetch({:killmail, killmail_id, killmail_hash}), do: get_killmail(killmail_id, killmail_hash)
  def fetch(_), do: {:error, Error.esi_error(:unsupported, "Unsupported fetch operation")}

  @impl DataFetcher
  def fetch_many(fetch_args) when is_list(fetch_args) do
    Enum.map(fetch_args, &fetch/1)
  end

  @impl DataFetcher
  def supports?({:killmail, _, _}), do: true
  def supports?(_), do: false

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp fetch_and_cache_killmail(killmail_id, killmail_hash, cache_key) do
    url = "#{esi_base_url()}/killmails/#{killmail_id}/#{killmail_hash}/"

    Logger.debug("Fetching killmail from ESI",
      killmail_id: killmail_id,
      killmail_hash: String.slice(killmail_hash, 0, 8) <> "..."
    )

    case http_client().get(url, default_headers(), request_options()) do
      {:ok, response} ->
        killmail = parse_killmail_response(killmail_id, killmail_hash, response)

        case Cache.put_with_ttl(:esi_cache, cache_key, killmail, cache_ttl()) do
          :ok ->
            Logger.debug("Successfully cached killmail", killmail_id: killmail_id)
            {:ok, killmail}

          {:error, reason} ->
            Logger.warning("Failed to cache killmail but fetch succeeded",
              killmail_id: killmail_id,
              reason: reason
            )

            {:ok, killmail}
        end

      {:error, %{status: 404}} ->
        Logger.debug("Killmail not found", killmail_id: killmail_id)

        {:error,
         Error.esi_error(:not_found, "Killmail not found", %{
           killmail_id: killmail_id,
           killmail_hash: killmail_hash
         })}

      {:error, %{status: 403}} ->
        Logger.debug("Killmail access forbidden", killmail_id: killmail_id)

        {:error,
         Error.esi_error(:forbidden, "Killmail access forbidden", %{
           killmail_id: killmail_id,
           killmail_hash: killmail_hash
         })}

      {:error, %{status: status}} when status >= 500 ->
        Logger.error("ESI server error for killmail",
          killmail_id: killmail_id,
          status: status
        )

        {:error,
         Error.esi_error(:server_error, "ESI server error", %{
           killmail_id: killmail_id,
           killmail_hash: killmail_hash,
           status: status
         })}

      {:error, reason} ->
        Logger.error("Failed to fetch killmail from ESI",
          killmail_id: killmail_id,
          reason: inspect(reason)
        )

        {:error,
         Error.esi_error(:api_error, "Failed to fetch killmail from ESI", %{
           killmail_id: killmail_id,
           killmail_hash: killmail_hash,
           reason: reason
         })}
    end
  end

  defp parse_killmail_response(killmail_id, killmail_hash, %{body: body}) do
    killmail = Map.put(body, "killmail_id", killmail_id)
    Map.put(killmail, "killmail_hash", killmail_hash)
  end

  defp esi_base_url, do: Config.service_url(:esi)
  defp cache_ttl, do: Config.cache_ttl(:esi_killmail)
  defp http_client, do: Config.http_client()

  defp default_headers do
    [
      {"User-Agent", "WandererKills/1.0"},
      {"Accept", "application/json"}
    ]
  end

  defp request_options do
    [
      timeout: Config.request_timeout(:esi),
      recv_timeout: Config.request_timeout(:esi)
    ]
  end
end
