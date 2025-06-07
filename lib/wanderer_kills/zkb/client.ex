defmodule WandererKills.Zkb.Client do
  @moduledoc """
  API client for zKillboard.
  """

  @behaviour WandererKills.Zkb.ClientBehaviour

  require Logger
  alias WandererKills.Core.Http.Client, as: HttpClient
  alias WandererKills.Core.Error

  @user_agent "(wanderer-kills@proton.me; +https://github.com/wanderer-industries/wanderer-kills)"
  @base_url Application.compile_env(:wanderer_kills, :zkb_base_url)

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
      {:ok, response} ->
        case parse_response(response) do
          # ZKB API returns array with single killmail
          {:ok, [killmail]} ->
            {:ok, killmail}

          {:ok, []} ->
            {:error, Error.zkb_error(:not_found, "Killmail not found in zKillboard", false)}

          # Take first if multiple
          {:ok, killmails} when is_list(killmails) ->
            {:ok, List.first(killmails)}

          other ->
            other
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches killmails for a system from zKillboard.
  Returns {:ok, [killmail]} or {:error, reason}.
  """
  def fetch_system_killmails(system_id) do
    url = "#{base_url()}/systemID/#{system_id}/"
    params = build_query_params(no_items: true)

    Logger.info("[ZKB] Fetching system killmails",
      system_id: system_id,
      data_source: "zkillboard.com/api",
      request_type: "historical_data"
    )

    case HttpClient.get_with_rate_limit(url,
           params: params,
           headers: [{"user-agent", @user_agent}],
           # Increase to 60 seconds
           timeout: 60_000,
           receive_timeout: 60_000
         ) do
      {:ok, response} ->
        case parse_response(response) do
          {:ok, killmails} when is_list(killmails) ->
            # Validate and log the format of received killmails
            validate_zkb_format(killmails, system_id)

            # Convert ZKB reference format to partial killmail format for parser
            converted_killmails = convert_zkb_to_partial_format(killmails)

            Logger.info(
              "[ZKB] Converted #{length(killmails)} reference killmails to partial format"
            )

            {:ok, converted_killmails}

          other ->
            other
        end

      {:error, reason} ->
        {:error, reason}
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
            {:error,
             Error.zkb_error(
               :unexpected_response,
               "Expected list data for kill count but got different format",
               false
             )}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_system_kill_count(_system_id) do
    {:error,
     Error.validation_error(:invalid_format, "Invalid system ID format for zKillboard API")}
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
