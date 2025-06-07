defmodule WandererKills.Zkb.ClientBehaviour do
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
  Gets the kill count for a system.
  """
  @callback get_system_kill_count(integer()) :: {:ok, integer()} | {:error, term()}
end

defmodule WandererKills.Zkb.Client do
  @moduledoc """
  Unified ZKB API client for zKillboard with telemetry and processing.

  This module consolidates ZKB API interactions with telemetry, logging,
  and processing functionality. It replaces the previous split architecture
  with a single unified approach.
  """

  @behaviour WandererKills.Zkb.ClientBehaviour

  require Logger
  alias WandererKills.Infrastructure.{Config, Error}
  alias WandererKills.Http.{Client, ClientProvider}
  alias WandererKills.Observability.Telemetry

  @base_url Application.compile_env(:wanderer_kills, :zkb_base_url)

  @type killmail_id :: pos_integer()
  @type system_id :: pos_integer()
  @type killmail :: map()

  @doc """
  Fetches a killmail from zKillboard with telemetry.
  Returns {:ok, killmail} or {:error, reason}.
  """
  @spec fetch_killmail(killmail_id()) :: {:ok, killmail()} | {:error, term()}
  def fetch_killmail(killmail_id) when is_integer(killmail_id) and killmail_id > 0 do
    Logger.debug("Fetching killmail from ZKB",
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

    Logger.info("[ZKB] Fetching system killmails",
      system_id: system_id,
      data_source: "zkillboard.com/api",
      request_type: "historical_data"
    )

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

            # Convert ZKB reference format to partial killmail format for parser
            converted_killmails = convert_zkb_to_partial_format(killmails)

            Logger.info(
              "[ZKB] Converted #{length(killmails)} reference killmails to partial format"
            )

            {:ok, converted_killmails}

          other ->
            Telemetry.fetch_system_error(system_id, other, :zkb)

            Logger.error("Failed to fetch system killmails from ZKB",
              system_id: system_id,
              operation: :fetch_system_killmails,
              error: other,
              step: :error
            )

            other
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

    request_opts = Keyword.put(request_opts, :operation, :"fetch_#{entity_type}_killmails")

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
  Gets the kill count for a system from zKillboard with telemetry.
  Returns {:ok, count} or {:error, reason}.
  """
  @spec get_system_kill_count(system_id()) :: {:ok, integer()} | {:error, term()}
  def get_system_kill_count(system_id) when is_integer(system_id) and system_id > 0 do
    Logger.debug("Fetching system kill count from ZKB",
      system_id: system_id,
      operation: :get_system_kill_count,
      step: :start
    )

    url = "#{base_url()}/systemID/#{system_id}/"

    request_opts =
      ClientProvider.build_request_opts(
        headers: ClientProvider.eve_api_headers(),
        timeout: Config.timeouts().zkb_request_ms
      )

    request_opts = Keyword.put(request_opts, :operation, :get_system_kill_count)

    case Client.request_with_telemetry(url, :zkb, request_opts) do
      {:ok, response} ->
        case Client.parse_json_response(response) do
          {:ok, data} when is_list(data) ->
            count = length(data)

            Logger.debug("Successfully fetched system kill count from ZKB",
              system_id: system_id,
              kill_count: count,
              operation: :get_system_kill_count,
              step: :success
            )

            {:ok, count}

          {:ok, _} ->
            error_reason =
              Error.zkb_error(
                :unexpected_response,
                "Expected list data for kill count but got different format",
                false
              )

            Logger.error("Failed to fetch system kill count from ZKB",
              system_id: system_id,
              operation: :get_system_kill_count,
              error: error_reason,
              step: :error
            )

            {:error, error_reason}

          {:error, reason} ->
            Logger.error("Failed to fetch system kill count from ZKB",
              system_id: system_id,
              operation: :get_system_kill_count,
              error: reason,
              step: :error
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch system kill count from ZKB",
          system_id: system_id,
          operation: :get_system_kill_count,
          error: reason,
          step: :error
        )

        {:error, reason}
    end
  end

  def get_system_kill_count(invalid_id) do
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
        {:error, _reason} -> do_fetch_active_systems()
      end
    end
  end

  defp fetch_from_cache do
    alias WandererKills.Cache.Helper

    case Helper.system_get_active_systems() do
      {:ok, systems} when is_list(systems) ->
        {:ok, systems}

      {:error, reason} ->
        Logger.warning("Cache error for active systems, falling back to fresh fetch",
          operation: :fetch_active_systems,
          step: :cache_error,
          error: reason
        )

        do_fetch_active_systems()
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

  # Note: Query parameter building now handled by WandererKills.Core.Http.Util

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
    @base_url
  end

  # Note: Response parsing now handled by WandererKills.Core.Http.Util

  # Converts ZKB reference format to partial killmail format expected by parser.
  # ZKB format: %{"killmail_id" => id, "zkb" => metadata}
  # Partial format: %{"killID" => id, "zkb" => metadata}
  defp convert_zkb_to_partial_format(zkb_killmails) when is_list(zkb_killmails) do
    Enum.map(zkb_killmails, &convert_single_zkb_killmail/1)
  end

  defp convert_single_zkb_killmail(%{"killmail_id" => id, "zkb" => zkb_data}) do
    %{
      "killID" => id,
      "zkb" => zkb_data
    }
  end

  defp convert_single_zkb_killmail(killmail) do
    Logger.warning("[ZKB] Unexpected killmail format, passing through unchanged",
      killmail_keys: Map.keys(killmail),
      killmail_sample: inspect(killmail, limit: 3)
    )

    killmail
  end

  @doc """
  Validates and logs the format of killmails received from zKillboard API.
  This helps us understand the data structure and compare it with RedisQ formats.
  """
  def validate_zkb_format(killmails, system_id) when is_list(killmails) do
    if length(killmails) > 0 do
      sample_killmail = List.first(killmails)
      format_analysis = analyze_killmail_structure(sample_killmail)

      Logger.info("[ZKB] Format Analysis",
        system_id: system_id,
        data_source: "zkillboard.com/api",
        killmail_count: length(killmails),
        sample_structure: format_analysis,
        data_type: "historical_killmails"
      )

      # Log detailed structure for first few killmails
      killmails
      |> Enum.take(3)
      |> Enum.with_index()
      |> Enum.each(fn {killmail, index} ->
        structure = analyze_killmail_structure(killmail)

        # Log the raw killmail structure for debugging
        Logger.info("[ZKB] Killmail RAW data",
          sample_index: index,
          killmail_id: Map.get(killmail, "killmail_id") || Map.get(killmail, "killID"),
          raw_keys: Map.keys(killmail),
          raw_structure: killmail |> inspect(limit: :infinity),
          byte_size: byte_size(inspect(killmail))
        )

        Logger.debug("[ZKB] Killmail structure detail",
          sample_index: index,
          killmail_id: Map.get(killmail, "killmail_id") || Map.get(killmail, "killID"),
          structure: structure,
          has_full_data: has_full_killmail_data?(killmail),
          needs_esi_fetch: needs_esi_fetch?(killmail)
        )
      end)

      # Track format statistics
      track_zkb_format_usage(format_analysis)
    else
      Logger.info("[ZKB] No killmails received",
        system_id: system_id,
        data_source: "zkillboard.com/api"
      )
    end
  end

  # Analyze the structure of a killmail to understand its format
  defp analyze_killmail_structure(killmail) when is_map(killmail) do
    %{
      has_killmail_id: Map.has_key?(killmail, "killmail_id"),
      has_killID: Map.has_key?(killmail, "killID"),
      has_victim: Map.has_key?(killmail, "victim"),
      has_attackers: Map.has_key?(killmail, "attackers"),
      has_solar_system_id: Map.has_key?(killmail, "solar_system_id"),
      has_zkb: Map.has_key?(killmail, "zkb"),
      has_hash: Map.has_key?(killmail, "hash"),
      main_keys: Map.keys(killmail) |> Enum.sort(),
      estimated_format: estimate_format_type(killmail)
    }
  end

  # Determine if killmail has full ESI-style data
  defp has_full_killmail_data?(killmail) do
    required_fields = ["victim", "attackers", "solar_system_id"]
    Enum.all?(required_fields, &Map.has_key?(killmail, &1))
  end

  # ZKB API confirmed to always return reference format requiring ESI fetch
  defp needs_esi_fetch?(killmail) do
    # ZKB API always returns reference format (killmail_id + zkb metadata only)
    Map.has_key?(killmail, "killmail_id") && Map.has_key?(killmail, "zkb")
  end

  # Estimate the format type - ZKB API is consistently reference format
  defp estimate_format_type(killmail) do
    cond do
      # Should not occur with ZKB API
      has_full_killmail_data?(killmail) ->
        :full_esi_format

      Map.has_key?(killmail, "killmail_id") && Map.has_key?(killmail, "zkb") ->
        :zkb_reference_format

      true ->
        :unknown_format
    end
  end

  # Track ZKB format usage for comparison with RedisQ
  defp track_zkb_format_usage(format_analysis) do
    format_type = format_analysis.estimated_format

    # Emit telemetry event
    :telemetry.execute(
      [:wanderer_kills, :zkb, :format],
      %{count: 1},
      %{
        format: format_type,
        data_source: "zkillboard_api",
        timestamp: DateTime.utc_now(),
        module: __MODULE__,
        analysis: format_analysis
      }
    )

    # Update persistent counters for periodic summaries
    current_stats = :persistent_term.get({__MODULE__, :zkb_format_stats}, %{})
    updated_stats = Map.update(current_stats, format_type, 1, &(&1 + 1))
    :persistent_term.put({__MODULE__, :zkb_format_stats}, updated_stats)

    new_count = :persistent_term.get({__MODULE__, :zkb_format_counter}, 0) + 1
    :persistent_term.put({__MODULE__, :zkb_format_counter}, new_count)

    # Log summary every 50 killmails
    if rem(new_count, 50) == 0 do
      log_zkb_format_summary(updated_stats, new_count)
    end
  end

  # Log comprehensive ZKB format summary
  defp log_zkb_format_summary(stats, total_count) do
    Logger.info("[ZKB] Format Summary",
      data_source: "zkillboard.com/api (historical)",
      total_killmails_analyzed: total_count,
      format_distribution: stats,
      purpose: "Format validation for preloader vs RedisQ comparison"
    )

    Enum.each(stats, fn {format, count} ->
      percentage = Float.round(count / total_count * 100, 1)
      recommendation = get_zkb_format_recommendation(format, percentage)

      Logger.info("[ZKB] Format details",
        format: format,
        count: count,
        percentage: "#{percentage}%",
        description: describe_zkb_format(format),
        recommendation: recommendation
      )
    end)
  end

  # Describe ZKB format types
  defp describe_zkb_format(:full_esi_format),
    do: "Complete killmail with victim/attackers (unexpected for ZKB API)"

  defp describe_zkb_format(:zkb_reference_format),
    do: "zKillboard reference format (killmail_id + zkb metadata) - confirmed production format"

  defp describe_zkb_format(:unknown_format), do: "Unknown/unexpected format"

  # Provide recommendations for ZKB formats
  defp get_zkb_format_recommendation(:full_esi_format, _),
    do: "UNEXPECTED: ZKB API should only return reference format"

  defp get_zkb_format_recommendation(:zkb_reference_format, _),
    do: "EXPECTED: Standard ZKB reference format - uses partial parser + ESI fetch"

  defp get_zkb_format_recommendation(:unknown_format, _), do: "ERROR: Review data structure"
end
