defmodule WandererKills.Parser.Enricher do
  @moduledoc """
  Enriches killmails with additional information.
  """

  require Logger
  alias WandererKills.Config
  alias WandererKills.Esi.Cache, as: EsiCache
  alias WandererKills.Data.ShipTypeInfo

  @doc """
  Enriches a killmail with additional information.
  """
  def enrich_killmail(killmail) do
    with {:ok, killmail} <- enrich_victim(killmail),
         {:ok, killmail} <- enrich_attackers(killmail),
         {:ok, killmail} <- enrich_ship(killmail) do
      {:ok, killmail}
    else
      error ->
        Logger.error("Failed to enrich killmail: #{inspect(error)}")
        error
    end
  end

  defp enrich_victim(killmail) do
    victim = Map.get(killmail, "victim", %{})

    with {:ok, character} <- get_character_info(Map.get(victim, "character_id")),
         {:ok, corporation} <- get_corporation_info(Map.get(victim, "corporation_id")),
         {:ok, alliance} <- get_alliance_info(Map.get(victim, "alliance_id")) do
      victim = Map.put(victim, "character", character)
      victim = Map.put(victim, "corporation", corporation)
      victim = Map.put(victim, "alliance", alliance)
      killmail = Map.put(killmail, "victim", victim)
      {:ok, killmail}
    end
  end

  defp enrich_attackers(killmail) do
    attackers = Map.get(killmail, "attackers", [])
    enricher_config = Config.enricher()

    enriched_attackers =
      if length(attackers) >= enricher_config.min_attackers_for_parallel do
        process_attackers_parallel(attackers, enricher_config)
      else
        process_attackers_sequential(attackers)
      end

    {:ok, Map.put(killmail, "attackers", enriched_attackers)}
  end

  @spec process_attackers_parallel([map()], map()) :: [map()]
  defp process_attackers_parallel(attackers, enricher_config) when is_list(attackers) do
    Task.Supervisor.async_stream_nolink(
      WandererKills.TaskSupervisor,
      attackers,
      fn attacker ->
        case enrich_attacker(attacker) do
          {:ok, enriched} -> {:ok, enriched}
          {:error, _} -> {:ok, nil}
        end
      end,
      max_concurrency: enricher_config.max_concurrency,
      timeout: enricher_config.task_timeout_ms
    )
    |> Stream.map(fn
      {:ok, result} -> result
      {:exit, _} -> nil
    end)
    |> Stream.filter(& &1)
    |> Enum.to_list()
  end

  @spec process_attackers_sequential([map()]) :: [map()]
  defp process_attackers_sequential(attackers) when is_list(attackers) do
    Enum.map(attackers, fn attacker ->
      case enrich_attacker(attacker) do
        {:ok, enriched} -> enriched
        {:error, _} -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  @spec enrich_attacker(map()) :: {:ok, map()} | {:error, term()}
  defp enrich_attacker(attacker) do
    with {:ok, character} <- get_character_info(Map.get(attacker, "character_id")),
         {:ok, corporation} <- get_corporation_info(Map.get(attacker, "corporation_id")),
         {:ok, alliance} <- get_alliance_info(Map.get(attacker, "alliance_id")) do
      attacker = Map.put(attacker, "character", character)
      attacker = Map.put(attacker, "corporation", corporation)
      attacker = Map.put(attacker, "alliance", alliance)
      {:ok, attacker}
    else
      error ->
        Logger.warning("Failed to enrich attacker: #{inspect(error)}")
        {:error, error}
    end
  end

  defp enrich_ship(killmail) do
    victim = Map.get(killmail, "victim", %{})

    with {:ok, ship} <- ShipTypeInfo.get_ship_type(Map.get(victim, "ship_type_id")) do
      victim = Map.put(victim, "ship", ship)
      killmail = Map.put(killmail, "victim", victim)
      {:ok, killmail}
    end
  end

  defp get_character_info(id) when is_integer(id), do: EsiCache.get_character_info(id)
  defp get_character_info(_), do: {:ok, nil}

  defp get_corporation_info(id) when is_integer(id), do: EsiCache.get_corporation_info(id)
  defp get_corporation_info(_), do: {:ok, nil}

  defp get_alliance_info(id) when is_integer(id), do: EsiCache.get_alliance_info(id)
  defp get_alliance_info(_), do: {:ok, nil}
end
