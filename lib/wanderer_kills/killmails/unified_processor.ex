defmodule WandererKills.Killmails.UnifiedProcessor do
  @moduledoc """
  Unified killmail processing that handles both full and partial killmails.

  This module eliminates the duplication between full and partial killmail
  processing by providing a single entry point that automatically detects
  the killmail type and processes accordingly.
  """

  require Logger
  import WandererKills.Support.Logger

  alias WandererKills.Support.Error
  alias WandererKills.Killmails.Transformations
  alias WandererKills.Killmails.Pipeline.{UnifiedValidator, DataBuilder, ESIFetcher}
  alias WandererKills.Killmails.Enrichment.BatchEnricher
  alias WandererKills.Storage.KillmailStore
  alias WandererKills.Observability.Monitoring

  @type killmail :: map()
  @type process_options :: [
          store: boolean(),
          enrich: boolean(),
          validate_only: boolean()
        ]
  @type process_result :: {:ok, killmail()} | {:ok, :kill_older} | {:error, term()}

  @doc """
  Processes any killmail, automatically detecting if it's full or partial.

  ## Parameters
  - `killmail` - The killmail data (full or partial)
  - `cutoff_time` - DateTime cutoff for filtering old killmails
  - `opts` - Processing options:
    - `:store` - Whether to store the killmail (default: true)
    - `:enrich` - Whether to enrich with ESI data (default: true)
    - `:validate_only` - Only validate, don't process (default: false)

  ## Returns
  - `{:ok, processed_killmail}` - On successful processing
  - `{:ok, :kill_older}` - When killmail is older than cutoff
  - `{:error, reason}` - On failure
  """
  @spec process_killmail(map(), DateTime.t(), process_options()) :: process_result()
  def process_killmail(killmail, cutoff_time, opts \\ []) when is_map(killmail) do
    # Normalize field names first
    normalized = Transformations.normalize_field_names(killmail)

    # Determine if this is a partial or full killmail
    result =
      cond do
        partial_killmail?(normalized) ->
          process_partial(normalized, cutoff_time, opts)

        full_killmail?(normalized) ->
          process_full(normalized, cutoff_time, opts)

        true ->
          {:error, Error.killmail_error(:invalid_format, "Unknown killmail format")}
      end

    # Monitor the result at the entry point level
    case result do
      {:ok, :kill_older} ->
        Monitoring.increment_skipped()
        result

      {:ok, _killmail} ->
        Monitoring.increment_stored()
        result

      {:error, _reason} ->
        result
    end
  end

  @doc """
  Processes a batch of killmails concurrently.

  ## Parameters
  - `killmails` - List of killmail data
  - `cutoff_time` - DateTime cutoff for filtering
  - `opts` - Processing options

  ## Returns
  - `{:ok, processed_killmails}` - List of successfully processed killmails
  """
  @spec process_batch([map()], DateTime.t(), process_options()) :: {:ok, [killmail()]}
  def process_batch(killmails, cutoff_time, opts \\ []) when is_list(killmails) do
    enrich? = Keyword.get(opts, :enrich, true)
    store? = Keyword.get(opts, :store, true)
    validate_only? = Keyword.get(opts, :validate_only, false)

    # Process all killmails through validation and data building first
    validated_killmails =
      killmails
      |> Enum.map(&Transformations.normalize_field_names/1)
      |> Enum.map(&validate_and_build_killmail(&1, cutoff_time))
      |> collect_valid_killmails()

    if validate_only? do
      {:ok, validated_killmails}
    else
      # Batch enrich all valid killmails if enrichment is enabled
      final_killmails =
        if enrich? and not Enum.empty?(validated_killmails) do
          case BatchEnricher.enrich_killmails_batch(validated_killmails) do
            {:ok, enriched} ->
              # Cache all enriched killmails
              Enum.each(enriched, &ESIFetcher.cache_enriched_killmail/1)
              enriched

            {:error, reason} ->
              Logger.error("Failed to enrich killmails batch",
                reason: reason,
                batch_size: length(validated_killmails)
              )

              # Fall back to unenriched killmails
              Enum.each(validated_killmails, &ESIFetcher.cache_enriched_killmail/1)
              validated_killmails
          end
        else
          Enum.each(validated_killmails, &ESIFetcher.cache_enriched_killmail/1)
          validated_killmails
        end

      # Store killmails if requested
      if store? do
        Enum.each(final_killmails, &store_killmail_async/1)
      end

      # Monitoring is handled at the entry point level
      {:ok, final_killmails}
    end
  end

  # Private functions

  defp partial_killmail?(killmail) do
    # Partial killmails have zkb data but no victim/attacker data
    Map.has_key?(killmail, "zkb") and
      not Map.has_key?(killmail, "victim") and
      not Map.has_key?(killmail, "attackers")
  end

  defp full_killmail?(killmail) do
    # Full killmails have the required ESI fields
    Map.has_key?(killmail, "victim") and
      Map.has_key?(killmail, "attackers") and
      (Map.has_key?(killmail, "system_id") or Map.has_key?(killmail, "solar_system_id"))
  end

  defp process_partial(partial, cutoff_time, opts) do
    case {partial["killmail_id"], partial["zkb"]} do
      {id, zkb} when is_integer(id) and is_map(zkb) ->
        log_debug("Processing partial killmail", killmail_id: id)

        case fetch_and_merge_partial(id, zkb, partial) do
          {:ok, merged} ->
            process_full(merged, cutoff_time, opts)

          {:error, reason} ->
            log_error("Failed to fetch full killmail data",
              killmail_id: id,
              error: reason
            )

            {:error, reason}
        end

      _ ->
        {:error,
         Error.killmail_error(
           :invalid_partial_format,
           "Partial killmail must have killmail_id and zkb fields"
         )}
    end
  end

  defp process_full(killmail, cutoff_time, opts) do
    store? = Keyword.get(opts, :store, true)
    enrich? = Keyword.get(opts, :enrich, true)
    validate_only? = Keyword.get(opts, :validate_only, false)

    killmail_id = Transformations.get_killmail_id(killmail)

    log_debug("Processing full killmail",
      killmail_id: killmail_id,
      store: store?,
      enrich: enrich?,
      validate_only: validate_only?
    )

    # Use unified validator
    case UnifiedValidator.validate_killmail(killmail, cutoff_time) do
      {:ok, validated} ->
        if validate_only? do
          {:ok, validated}
        else
          process_validated_killmail(validated, store?, enrich?)
        end

      {:error, %Error{type: :kill_too_old}} ->
        {:ok, :kill_older}

      {:error, reason} ->
        log_error("Killmail validation failed",
          killmail_id: killmail_id,
          error: reason
        )

        {:error, reason}
    end
  end

  defp process_validated_killmail(killmail, store?, enrich?) do
    with {:ok, built} <- DataBuilder.build_killmail_data(killmail),
         {:ok, processed} <- maybe_enrich(built, enrich?) do
      if store? do
        store_killmail_async(processed)
      end

      {:ok, processed}
    end
  end

  defp maybe_enrich(killmail, true) do
    # Import enrichment logic from original Processor
    case enrich_killmail(killmail) do
      {:ok, enriched} ->
        ESIFetcher.cache_enriched_killmail(enriched)
        {:ok, enriched}

      _ ->
        log_warning("Failed to enrich killmail, using basic data",
          killmail_id: killmail["killmail_id"]
        )

        ESIFetcher.cache_enriched_killmail(killmail)
        {:ok, killmail}
    end
  end

  defp maybe_enrich(killmail, false) do
    ESIFetcher.cache_enriched_killmail(killmail)
    {:ok, killmail}
  end

  defp store_killmail_async(killmail) do
    case extract_system_id(killmail) do
      {:ok, system_id} ->
        Task.Supervisor.start_child(WandererKills.TaskSupervisor, fn ->
          log_debug("Storing killmail asynchronously",
            killmail_id: killmail["killmail_id"],
            system_id: system_id
          )

          KillmailStore.put(killmail["killmail_id"], system_id, killmail)
        end)

      {:error, reason} ->
        log_error("Cannot store killmail without system_id",
          killmail_id: killmail["killmail_id"],
          error: reason
        )

        {:error, reason}
    end
  end

  defp extract_system_id(%{"solar_system_id" => id}) when not is_nil(id), do: {:ok, id}
  defp extract_system_id(%{"system_id" => id}) when not is_nil(id), do: {:ok, id}

  defp extract_system_id(killmail) do
    log_warning("Killmail missing system_id", killmail_id: killmail["killmail_id"])
    {:error, :missing_system_id}
  end

  defp validate_and_build_killmail(killmail, cutoff_time) do
    case UnifiedValidator.validate_killmail(killmail, cutoff_time) do
      {:ok, validated} ->
        DataBuilder.build_killmail_data(validated)

      error ->
        error
    end
  end

  defp collect_valid_killmails(results) do
    results
    |> Enum.reduce([], fn
      {:ok, killmail}, acc -> [killmail | acc]
      {:error, %Error{type: :kill_too_old}}, acc -> acc
      {:error, _}, acc -> acc
    end)
    |> Enum.reverse()
  end

  defp enrich_killmail(killmail) do
    {:ok, enriched_list} = BatchEnricher.enrich_killmails_batch([killmail])

    case enriched_list do
      [enriched_killmail] -> {:ok, enriched_killmail}
      [] -> {:error, :enrichment_failed}
    end
  end

  defp fetch_and_merge_partial(id, zkb, partial) do
    case ESIFetcher.fetch_full_killmail(id, zkb) do
      {:ok, full_data} ->
        log_debug("ESI data fetched",
          killmail_id: id,
          esi_keys: Map.keys(full_data) |> Enum.sort(),
          has_killmail_time: Map.has_key?(full_data, "killmail_time"),
          has_kill_time: Map.has_key?(full_data, "kill_time")
        )

        # Normalize field names before merging
        normalized_data = Transformations.normalize_field_names(full_data)

        log_debug("After normalization",
          killmail_id: id,
          normalized_keys: Map.keys(normalized_data) |> Enum.sort(),
          has_kill_time: Map.has_key?(normalized_data, "kill_time")
        )

        DataBuilder.merge_killmail_data(normalized_data, partial)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
