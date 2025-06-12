defmodule WandererKills.Killmails.ZkbClientBehaviour do
  @moduledoc """
  Behaviour for ZKB (zKillboard) client implementations.
  """

  @doc """
  Fetches a killmail from zKillboard.
  """
  @callback fetch_killmail(integer()) :: {:ok, map()} | {:error, term()}

  @doc """
  Fetches killmails for a system from zKillboard.
  """
  @callback fetch_system_killmails(integer()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Gets the killmail count for a system.
  """
  @callback get_system_killmail_count(integer()) :: {:ok, integer()} | {:error, term()}
end

defmodule WandererKills.Killmails.ZkbClient do
  @moduledoc """
  Unified ZKB API client for zKillboard with telemetry and processing.

  This module consolidates ZKB API interactions with telemetry, logging,
  and processing functionality. It replaces the previous split architecture
  with a single unified approach.
  """

  @behaviour WandererKills.Killmails.ZkbClientBehaviour

  require Logger
  import WandererKills.Support.Logger
  alias WandererKills.Support.Error
  alias WandererKills.Http.{Client, ClientProvider}
  alias WandererKills.Observability.Telemetry
  alias WandererKills.Config

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type killmail :: map()

  @doc """
  Fetches a killmail from zKillboard with telemetry.
  Returns {:ok, killmail} or {:error, reason}.
  """
  @spec fetch_killmail(killmail_id()) :: {:ok, killmail()} | {:error, term()}
  def fetch_killmail(killmail_id) when is_integer(killmail_id) and killmail_id > 0 do
    log_debug("Fetching killmail from ZKB",
      killmail_id: killmail_id,
      operation: :fetch_killmail,
      step: :start
    )

    Telemetry.fetch_system_start(killmail_id, 1, :zkb)

    url = "#{base_url()}/killID/#{killmail_id}/"

    request_opts =
      ClientProvider.build_request_opts(
        params: [no_items: true],
        headers: ClientProvider.eve_api_headers(),
        timeout: Config.timeouts().zkb_request_ms
      )

    request_opts = Keyword.put(request_opts, :operation, :fetch_killmail)

    case Client.request_with_telemetry(url, :zkb, request_opts) do
      {:ok, response} ->
        case Client.parse_json_response(response) do
          # ZKB API returns array with single killmail
          {:ok, [killmail]} ->
            Telemetry.fetch_system_complete(killmail_id, :success)
            {:ok, killmail}

          {:ok, []} ->
            Telemetry.fetch_system_error(killmail_id, :not_found, :zkb)
            {:error, Error.zkb_error(:not_found, "Killmail not found in zKillboard", false)}

          # Take first if multiple
          {:ok, killmails} when is_list(killmails) ->
            Telemetry.fetch_system_complete(killmail_id, :success)
            {:ok, List.first(killmails)}

          {:error, reason} ->
            Telemetry.fetch_system_error(killmail_id, reason, :zkb)
            {:error, reason}
        end

      {:error, reason} ->
        Telemetry.fetch_system_error(killmail_id, reason, :zkb)
        {:error, reason}
    end
  end

  def fetch_killmail(invalid_id) do
    {:error,
     Error.validation_error(:invalid_format, "Invalid killmail ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Fetches killmails for a system from zKillboard with telemetry.
  Returns {:ok, [killmail]} or {:error, reason}.
  """
  @spec fetch_system_killmails(system_id()) :: {:ok, [killmail()]} | {:error, term()}
  def fetch_system_killmails(system_id) when is_integer(system_id) and system_id > 0 do
    Logger.debug("Fetching system killmails from ZKB",
      system_id: system_id,
      operation: :fetch_system_killmails,
      step: :start
    )

    Telemetry.fetch_system_start(system_id, 0, :zkb)

    url = "#{base_url()}/systemID/#{system_id}/"

    Logger.debug("[ZKB] Fetching system killmails", %{
      system_id: system_id,
      data_source: "zkillboard.com/api",
      request_type: "historical_data"
    })

    request_opts =
      ClientProvider.build_request_opts(
        params: [no_items: true],
        headers: ClientProvider.eve_api_headers(),
        timeout: 60_000
      )

    request_opts = Keyword.put(request_opts, :operation, :fetch_system_killmails)

    case Client.request_with_telemetry(url, :zkb, request_opts) do
      {:ok, response} ->
        case Client.parse_json_response(response) do
          {:ok, killmails} when is_list(killmails) ->
            Telemetry.fetch_system_success(system_id, length(killmails), :zkb)

            Logger.debug("Successfully fetched system killmails from ZKB",
              system_id: system_id,
              killmail_count: length(killmails),
              operation: :fetch_system_killmails,
              step: :success
            )

            # Validate and log the format of received killmails
            validate_zkb_format(killmails, system_id)

            {:ok, killmails}

          {:error, reason} ->
            Telemetry.fetch_system_error(system_id, reason, :zkb)

            Logger.error("Failed to fetch system killmails from ZKB",
              system_id: system_id,
              operation: :fetch_system_killmails,
              error: reason,
              step: :error
            )

            {:error, reason}

          other ->
            # Handle unexpected successful responses
            error_reason =
              Error.zkb_error(:unexpected_response, "Unexpected response format from ZKB", false)

            Telemetry.fetch_system_error(system_id, error_reason, :zkb)

            Logger.error("Failed to fetch system killmails from ZKB",
              system_id: system_id,
              operation: :fetch_system_killmails,
              error: error_reason,
              unexpected_response: other,
              step: :error
            )

            {:error, error_reason}
        end

      {:error, reason} ->
        Telemetry.fetch_system_error(system_id, reason, :zkb)

        Logger.error("Failed to fetch system killmails from ZKB",
          system_id: system_id,
          operation: :fetch_system_killmails,
          error: reason,
          step: :error
        )

        {:error, reason}
    end
  end

  def fetch_system_killmails(invalid_id) do
    {:error,
     Error.validation_error(:invalid_format, "Invalid system ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Fetches killmails for a system from zKillboard with telemetry (compatibility function).
  The limit and since_hours parameters are currently ignored but kept for API compatibility.
  """
  @spec fetch_system_killmails(system_id(), pos_integer(), pos_integer()) ::
          {:ok, [killmail()]} | {:error, term()}
  def fetch_system_killmails(system_id, _limit, _since_hours)
      when is_integer(system_id) and system_id > 0 do
    # For now, delegate to the main function - in the future we could use limit/since_hours
    fetch_system_killmails(system_id)
  end

  def fetch_system_killmails(invalid_id, _limit, _since_hours) do
    {:error,
     Error.validation_error(:invalid_format, "Invalid system ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Gets killmails for a corporation from zKillboard.
  """
  def get_corporation_killmails(corporation_id) do
    fetch_entity_killmails("corporationID", corporation_id)
  end

  @doc """
  Gets killmails for an alliance from zKillboard.
  """
  def get_alliance_killmails(alliance_id) do
    fetch_entity_killmails("allianceID", alliance_id)
  end

  @doc """
  Gets killmails for a character from zKillboard.
  """
  def get_character_killmails(character_id) do
    fetch_entity_killmails("characterID", character_id)
  end

  # Shared function for fetching killmails by entity type
  defp fetch_entity_killmails(entity_type, entity_id) do
    url = "#{base_url()}/#{entity_type}/#{entity_id}/"

    request_opts =
      ClientProvider.build_request_opts(
        params: [no_items: true],
        headers: ClientProvider.eve_api_headers(),
        timeout: Config.timeouts().zkb_request_ms
      )

    operation_atom =
      case entity_type do
        "systemID" -> :fetch_system_killmails
        "characterID" -> :fetch_character_killmails
        "corporationID" -> :fetch_corporation_killmails
        "allianceID" -> :fetch_alliance_killmails
        _ -> :fetch_unknown_killmails
      end

    request_opts = Keyword.put(request_opts, :operation, operation_atom)

    case Client.request_with_telemetry(url, :zkb, request_opts) do
      {:ok, response} -> Client.parse_json_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches killmails for a system from ESI.
  Returns {:ok, [killmail]} or {:error, reason}.
  """
  def fetch_system_killmails_esi(system_id) do
    url = "#{base_url()}/systemID/#{system_id}/"

    request_opts =
      ClientProvider.build_request_opts(
        headers: ClientProvider.eve_api_headers(),
        timeout: Config.timeouts().zkb_request_ms
      )

    request_opts = Keyword.put(request_opts, :operation, :fetch_system_killmails_esi)

    case Client.request_with_telemetry(url, :zkb, request_opts) do
      {:ok, response} -> Client.parse_json_response(response)
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
  Gets the killmail count for a system from zKillboard with telemetry.
  Returns {:ok, count} or {:error, reason}.
  """
  @spec get_system_killmail_count(system_id()) :: {:ok, integer()} | {:error, term()}
  def get_system_killmail_count(system_id) when is_integer(system_id) and system_id > 0 do
    Logger.debug("Fetching system killmail count from ZKB",
      system_id: system_id,
      operation: :get_system_killmail_count,
      step: :start
    )

    url = "#{base_url()}/systemID/#{system_id}/"

    request_opts =
      ClientProvider.build_request_opts(
        headers: ClientProvider.eve_api_headers(),
        timeout: Config.timeouts().zkb_request_ms
      )

    request_opts = Keyword.put(request_opts, :operation, :get_system_killmail_count)

    case Client.request_with_telemetry(url, :zkb, request_opts) do
      {:ok, response} ->
        case Client.parse_json_response(response) do
          {:ok, data} when is_list(data) ->
            count = length(data)

            Logger.debug("Successfully fetched system killmail count from ZKB",
              system_id: system_id,
              killmail_count: count,
              operation: :get_system_killmail_count,
              step: :success
            )

            {:ok, count}

          {:ok, _} ->
            error_reason =
              Error.zkb_error(
                :unexpected_response,
                "Expected list data for killmail count but got different format",
                false
              )

            Logger.error("Failed to fetch system killmail count from ZKB",
              system_id: system_id,
              operation: :get_system_killmail_count,
              error: error_reason,
              step: :error
            )

            {:error, error_reason}

          {:error, reason} ->
            Logger.error("Failed to fetch system killmail count from ZKB",
              system_id: system_id,
              operation: :get_system_killmail_count,
              error: reason,
              step: :error
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch system killmail count from ZKB",
          system_id: system_id,
          operation: :get_system_killmail_count,
          error: reason,
          step: :error
        )

        {:error, reason}
    end
  end

  def get_system_killmail_count(invalid_id) do
    {:error,
     Error.validation_error(:invalid_format, "Invalid system ID format: #{inspect(invalid_id)}")}
  end

  @doc """
  Fetches active systems from zKillboard with caching.
  """
  @spec fetch_active_systems(keyword()) :: {:ok, [system_id()]} | {:error, term()}
  def fetch_active_systems(opts \\ []) do
    force = Keyword.get(opts, :force, false)

    if force do
      do_fetch_active_systems()
    else
      case fetch_from_cache() do
        {:ok, systems} -> {:ok, systems}
      end
    end
  end

  defp fetch_from_cache do
    alias WandererKills.Cache.Helper

    case Helper.get_active_systems() do
      {:ok, systems} when is_list(systems) ->
        {:ok, systems}

      _ ->
        {:error, Error.cache_error(:not_found, "Active systems not found in cache")}
    end
  end

  defp do_fetch_active_systems do
    url = "#{base_url()}/systems/"

    request_opts =
      ClientProvider.build_request_opts(
        headers: ClientProvider.eve_api_headers(),
        timeout: Config.timeouts().zkb_request_ms
      )

    request_opts = Keyword.put(request_opts, :operation, :fetch_active_systems)

    case Client.request_with_telemetry(url, :zkb, request_opts) do
      {:ok, response} ->
        case Client.parse_json_response(response) do
          {:ok, systems} when is_list(systems) ->
            {:ok, systems}

          {:ok, _} ->
            {:error,
             Error.zkb_error(
               :unexpected_response,
               "Expected list of systems but got different format",
               false
             )}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Note: Query parameter building now handled by WandererKills.Http.Client

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
  Gets the base URL for zKillboard API calls.
  """
  def base_url do
    Config.zkb().base_url
  end

  # Note: Response parsing now handled by WandererKills.Http.Client

  @doc """
  Validates and logs the format of killmails received from zKillboard API.
  """
  def validate_zkb_format(killmails, system_id) when is_list(killmails) do
    log_debug("[ZKB] Received killmails",
      system_id: system_id,
      killmail_count: length(killmails),
      data_source: "zkillboard.com/api"
    )

    # Track format for telemetry if we have killmails
    if length(killmails) > 0 do
      sample = List.first(killmails)

      format_type =
        cond do
          Map.has_key?(sample, "victim") && Map.has_key?(sample, "attackers") ->
            :full_esi_format

          Map.has_key?(sample, "killmail_id") && Map.has_key?(sample, "zkb") ->
            :zkb_reference_format

          true ->
            :unknown_format
        end

      # Emit telemetry event
      WandererKills.Observability.Telemetry.zkb_format(format_type, %{
        source: :zkb_api,
        system_id: system_id,
        count: length(killmails)
      })
    end
  end
end
