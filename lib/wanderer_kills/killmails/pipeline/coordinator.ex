defmodule WandererKills.Killmails.Pipeline.Coordinator do
  @moduledoc """
  Main parser coordinator that handles the parsing pipeline.

  This module provides functionality to:
  - Parse full killmails from ESI
  - Parse partial killmails from system listings
  - Enrich killmail data with additional information
  - Store parsed killmails in the cache
  - Handle time-based filtering of killmails

  ## Features

  - Full killmail parsing and enrichment
  - Partial killmail handling with ESI fallback
  - Automatic data merging and validation
  - Time-based filtering of old killmails
  - Error handling and logging
  - Cache integration

  ## Usage

  ```elixir
  # Parse a full killmail
  {:ok, enriched} = Coordinator.parse_full_and_store(full_killmail, partial_killmail, cutoff_time)

  # Parse a partial killmail
  {:ok, enriched} = Coordinator.parse_partial(partial_killmail, cutoff_time)

  # Handle skipped kills
  {:ok, :kill_skipped} = Coordinator.parse_partial(old_killmail, cutoff_time)
  ```

  ## Data Flow

  1. Full killmails:
     - Merge full and partial data
     - Build kill data structure
     - Enrich with additional information
     - Store in cache

  2. Partial killmails:
     - Fetch full data from ESI
     - Process as full killmail
     - Skip if too old
     - Handle errors appropriately

  ## Error Handling

  All functions return either:
  - `{:ok, killmail}` - On successful parsing
  - `{:ok, :kill_skipped}` - When killmail is too old
  - `:older` - When killmail is older than cutoff
  - `{:error, Error.t()}` - On failure with standardized error
  """

  require Logger
  alias WandererKills.Support.Error
  alias WandererKills.Killmails.Pipeline.Parser
  alias WandererKills.Killmails.Transformations
  alias WandererKills.Storage.KillmailStore

  @type killmail :: map()
  @type raw_killmail :: map()

  @doc """
  Parses a full killmail with enrichment and stores it.

  ## Parameters
  - `full` - The full killmail data from ESI
  - `partial` - The partial killmail data with zkb info
  - `cutoff` - DateTime cutoff for filtering old killmails

  ## Returns
  - `{:ok, enriched_killmail}` - On successful parsing and enrichment
  - `{:error, Error.t()}` - On failure with standardized error

  ## Examples

  ```elixir
  # Parse a full killmail
  full = %{"killmail_id" => 12345, "victim" => %{...}}
  partial = %{"zkb" => %{"hash" => "abc123"}}
  cutoff = Clock.now()

  {:ok, enriched} = parse_full_and_store(full, partial, cutoff)

  # Handle invalid format
  {:error, %Error{}} = parse_full_and_store(invalid_data, invalid_data, cutoff)
  ```
  """
  @spec parse_full_and_store(killmail(), killmail(), DateTime.t()) ::
          {:ok, killmail()} | {:ok, :kill_older} | {:error, Error.t()}
  def parse_full_and_store(full, %{"zkb" => zkb}, cutoff) when is_map(full) do
    Logger.debug("Starting to parse and store killmail", %{
      killmail_id: full["killmail_id"],
      operation: :parse_full_and_store,
      step: :start
    })

    process_killmail(full, zkb, cutoff)
  end

  def parse_full_and_store(_, _, _) do
    {:error, Error.killmail_error(:invalid_format, "Invalid payload format for killmail parsing")}
  end

  @spec process_killmail(killmail(), map(), DateTime.t()) ::
          {:ok, killmail()} | {:ok, :kill_older} | {:error, Error.t()}
  defp process_killmail(full, zkb, cutoff) do
    # Merge zkb data into the full killmail
    merged = Map.put(full, "zkb", zkb)
    killmail_id = full["killmail_id"]

    merged
    |> parse_killmail_with_cutoff(cutoff, killmail_id)
    |> handle_parse_result(killmail_id)
  end

  defp handle_parse_result({:ok, :kill_older}, _killmail_id), do: {:ok, :kill_older}

  defp handle_parse_result({:ok, parsed}, killmail_id) do
    with {:ok, enriched} <- enrich_and_log_killmail(parsed, killmail_id),
         {:ok, system_id} <- extract_system_id(enriched, killmail_id) do
      store_killmail_async(system_id, enriched, killmail_id)
      {:ok, enriched}
    end
  end

  defp handle_parse_result({:error, reason}, _killmail_id), do: {:error, reason}

  @spec parse_killmail_with_cutoff(killmail(), DateTime.t(), term()) ::
          {:ok, killmail()} | {:ok, :kill_older} | {:error, Error.t()}
  defp parse_killmail_with_cutoff(merged, cutoff, killmail_id) do
    case Parser.parse_full_killmail(merged, cutoff) do
      {:ok, :kill_older} ->
        Logger.debug("Killmail is older than cutoff", %{
          killmail_id: killmail_id,
          operation: :process_killmail,
          status: :kill_older
        })

        {:ok, :kill_older}

      {:ok, parsed} ->
        {:ok, parsed}

      {:error, reason} ->
        Logger.error("Failed to parse killmail", %{
          killmail_id: killmail_id,
          operation: :process_killmail,
          error: reason,
          status: :error
        })

        {:error, reason}
    end
  end

  @spec enrich_and_log_killmail(killmail(), term()) :: {:ok, killmail()} | {:error, Error.t()}
  defp enrich_and_log_killmail(parsed, killmail_id) do
    case enrich_killmail(parsed) do
      {:ok, enriched} ->
        {:ok, enriched}

      {:error, reason} ->
        Logger.error("Failed to enrich killmail", %{
          killmail_id: killmail_id,
          operation: :process_killmail,
          error: reason,
          status: :error
        })

        {:error, reason}
    end
  end

  @spec extract_system_id(killmail(), term()) :: {:ok, integer()} | {:error, Error.t()}
  defp extract_system_id(%{"solar_system_id" => system_id}, _killmail_id)
       when not is_nil(system_id) do
    {:ok, system_id}
  end

  defp extract_system_id(%{"system_id" => system_id}, _killmail_id) when not is_nil(system_id) do
    {:ok, system_id}
  end

  defp extract_system_id(_enriched, killmail_id) do
    Logger.error("Missing system_id in enriched killmail", %{
      killmail_id: killmail_id,
      operation: :process_killmail,
      status: :error
    })

    {:error,
     Error.killmail_error(
       :missing_system_id,
       "System ID missing from enriched killmail",
       false,
       %{killmail_id: killmail_id}
     )}
  end

  @spec store_killmail_async(integer(), killmail(), term()) :: :ok
  defp store_killmail_async(system_id, enriched, killmail_id) do
    Task.start(fn ->
      try do
        killmail_id = enriched["killmail_id"]
        :ok = KillmailStore.put(killmail_id, system_id, enriched)

        Logger.debug("Successfully enriched and stored killmail", %{
          killmail_id: killmail_id,
          system_id: system_id,
          operation: :process_killmail,
          status: :success
        })
      rescue
        # Only rescue specific known exception types to avoid masking bugs
        error in [ArgumentError] ->
          Logger.error("Invalid arguments when storing killmail", %{
            killmail_id: killmail_id,
            system_id: system_id,
            operation: :process_killmail,
            error: Exception.message(error),
            status: :error
          })

        error in [BadMapError] ->
          Logger.error("Invalid killmail data structure", %{
            killmail_id: killmail_id,
            system_id: system_id,
            operation: :process_killmail,
            error: Exception.message(error),
            status: :error
          })
      end
    end)

    :ok
  end

  @spec enrich_killmail(killmail()) :: {:ok, killmail()} | {:error, Error.t()}
  defp enrich_killmail(killmail) do
    WandererKills.Killmails.Pipeline.Enricher.enrich_killmail(killmail)
  end

  @doc """
  Parses a partial killmail by fetching the full data from ESI.

  ## Parameters
  - `partial` - The partial killmail data with zkb info
  - `cutoff` - DateTime cutoff for filtering old killmails

  ## Returns
  - `{:ok, enriched_killmail}` - On successful parsing
  - `{:ok, :kill_skipped}` - When killmail is too old
  - `:older` - When killmail is older than cutoff
  - `{:error, Error.t()}` - On failure with standardized error

  ## Examples

  ```elixir
  # Parse a partial killmail
  partial = %{
    "killmail_id" => 12345,
    "zkb" => %{"hash" => "abc123"}
  }
  cutoff = Clock.now()

  {:ok, enriched} = parse_partial(partial, cutoff)

  # Handle old killmail
  {:ok, :kill_skipped} = parse_partial(old_killmail, cutoff)

  # Handle invalid format
  {:error, %Error{}} = parse_partial(invalid_data, cutoff)
  ```
  """
  @spec parse_partial(raw_killmail(), DateTime.t()) ::
          {:ok, killmail()} | {:ok, :kill_skipped} | :older | {:error, Error.t()}
  def parse_partial(partial, cutoff) when is_map(partial) do
    # Normalize field names first
    normalized = Transformations.normalize_field_names(partial)
    do_parse_partial(normalized, cutoff)
  end

  defp do_parse_partial(%{"killmail_id" => id, "zkb" => %{"hash" => hash}} = partial, cutoff) do
    Logger.debug("Starting to parse partial killmail", %{
      killmail_id: id,
      operation: :parse_partial,
      step: :start
    })

    case WandererKills.ESI.DataFetcher.get_killmail_raw(id, hash) do
      {:ok, full} ->
        Logger.debug("Successfully fetched full killmail from ESI", %{
          killmail_id: id,
          operation: :fetch_from_esi,
          status: :success
        })

        parse_full_and_store(full, partial, cutoff)

      {:error, reason} ->
        Logger.error("Failed to fetch full killmail", %{
          killmail_id: id,
          operation: :fetch_from_esi,
          error: reason,
          status: :error
        })

        {:error, reason}
    end
  end

  defp do_parse_partial(_, _) do
    {:error,
     Error.killmail_error(
       :invalid_format,
       "Invalid partial killmail format - missing required fields"
     )}
  end

  @doc """
  Processes a list of raw killmails from zKillboard.

  This function handles the complete processing pipeline:
  1. Parse raw killmails
  2. Filter by time constraints
  3. Enrich with additional data

  ## Parameters
  - `raw_killmails` - List of raw killmail data from ZKB
  - `system_id` - The system ID (used for logging)
  - `since_hours` - Only process killmails newer than this many hours

  ## Returns
  - `{:ok, [enriched_killmail]}` - On successful processing
  - `{:error, reason}` - On failure
  """
  @spec process_killmails([map()], pos_integer(), pos_integer()) ::
          {:ok, [killmail()]} | {:error, term()}
  def process_killmails(raw_killmails, system_id, since_hours)
      when is_list(raw_killmails) and is_integer(system_id) and is_integer(since_hours) do
    Logger.debug("Processing killmails",
      system_id: system_id,
      raw_count: length(raw_killmails),
      since_hours: since_hours,
      operation: :process_killmails,
      step: :start
    )

    with {:ok, parsed_killmails} <- parse_killmails(raw_killmails, since_hours),
         {:ok, enriched_killmails} <- enrich_killmails(parsed_killmails, system_id) do
      Logger.debug("Successfully processed killmails",
        system_id: system_id,
        raw_count: length(raw_killmails),
        parsed_count: length(parsed_killmails),
        enriched_count: length(enriched_killmails),
        operation: :process_killmails,
        step: :success
      )

      {:ok, enriched_killmails}
    else
      {:error, reason} ->
        Logger.error("Failed to process killmails",
          system_id: system_id,
          raw_count: length(raw_killmails),
          error: reason,
          operation: :process_killmails,
          step: :error
        )

        {:error, reason}
    end
  end

  def process_killmails(invalid_killmails, _system_id, _since_hours) do
    {:error,
     Error.validation_error(
       :invalid_type,
       "Killmails must be a list, got: #{inspect(invalid_killmails)}"
     )}
  end

  @doc """
  Processes a single killmail.
  """
  @spec process_single_killmail(map(), boolean()) :: {:ok, killmail()} | {:error, term()}
  def process_single_killmail(raw_killmail, enrich \\ true) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-24 * 60 * 60, :second)

    case Parser.parse_partial_killmail(raw_killmail, cutoff_time) do
      {:ok, parsed} when enrich ->
        case WandererKills.Killmails.Pipeline.Enricher.enrich_killmail(parsed) do
          {:ok, enriched} -> {:ok, enriched}
          # Fall back to basic data
          {:error, _reason} -> {:ok, parsed}
        end

      {:ok, parsed} ->
        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    # Only rescue specific known exception types
    error in [ArgumentError] ->
      Logger.error("Invalid arguments during killmail processing",
        error: Exception.message(error),
        operation: :process_single_killmail
      )

      {:error, Error.validation_error(:invalid_arguments, Exception.message(error))}

    error in [BadMapError] ->
      Logger.error("Invalid killmail data structure",
        error: Exception.message(error),
        operation: :process_single_killmail
      )

      {:error, Error.killmail_error(:invalid_format, Exception.message(error))}
  end

  @doc """
  Parses raw killmails with time filtering.
  """
  @spec parse_killmails([map()], pos_integer()) :: {:ok, [killmail()]} | {:error, term()}
  def parse_killmails(raw_killmails, since_hours)
      when is_list(raw_killmails) and is_integer(since_hours) do
    # Calculate cutoff time
    cutoff_time = DateTime.utc_now() |> DateTime.add(-since_hours * 60 * 60, :second)

    Logger.debug("Parsing killmails with time filter",
      raw_count: length(raw_killmails),
      since_hours: since_hours,
      cutoff_time: cutoff_time,
      operation: :parse_killmails,
      step: :start
    )

    parsed =
      raw_killmails
      |> Enum.map(&Parser.parse_partial_killmail(&1, cutoff_time))
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.flat_map(fn
        {:ok, killmail} when is_map(killmail) -> [killmail]
        {:ok, killmails} when is_list(killmails) -> killmails
      end)

    Logger.debug("Successfully parsed killmails",
      raw_count: length(raw_killmails),
      parsed_count: length(parsed),
      parser_type: "partial_killmail",
      cutoff_time: cutoff_time,
      operation: :parse_killmails,
      step: :success
    )

    {:ok, parsed}
  rescue
    error ->
      Logger.error("Exception during killmail parsing",
        raw_count: length(raw_killmails),
        error: inspect(error),
        operation: :parse_killmails,
        step: :exception
      )

      {:error, Error.parsing_error(:exception, "Exception during killmail parsing")}
  end

  def parse_killmails(invalid_killmails, _since_hours) do
    {:error,
     Error.validation_error(
       :invalid_type,
       "Killmails must be a list, got: #{inspect(invalid_killmails)}"
     )}
  end

  @doc """
  Enriches parsed killmails with additional information.
  """
  @spec enrich_killmails([killmail()], pos_integer()) :: {:ok, [killmail()]} | {:error, term()}
  def enrich_killmails(parsed_killmails, system_id)
      when is_list(parsed_killmails) and is_integer(system_id) do
    Logger.debug("Enriching killmails",
      system_id: system_id,
      parsed_count: length(parsed_killmails),
      operation: :enrich_killmails,
      step: :start
    )

    enriched =
      parsed_killmails
      |> Enum.map(fn killmail ->
        case WandererKills.Killmails.Pipeline.Enricher.enrich_killmail(killmail) do
          {:ok, enriched} ->
            enriched

          # Fall back to original if enrichment fails
          {:error, reason} ->
            Logger.debug("Enrichment failed for killmail, using basic data",
              killmail_id: Map.get(killmail, "killmail_id"),
              system_id: system_id,
              error: reason,
              operation: :enrich_killmails,
              step: :fallback
            )

            killmail
        end
      end)

    Logger.debug("Successfully enriched killmails",
      system_id: system_id,
      parsed_count: length(parsed_killmails),
      enriched_count: length(enriched),
      operation: :enrich_killmails,
      step: :success
    )

    {:ok, enriched}
  rescue
    error ->
      Logger.error("Exception during killmail enrichment",
        system_id: system_id,
        parsed_count: length(parsed_killmails),
        error: inspect(error),
        operation: :enrich_killmails,
        step: :exception
      )

      {:error, Error.enrichment_error(:exception, "Exception during killmail enrichment")}
  end

  def enrich_killmails(invalid_killmails, _system_id) do
    {:error,
     Error.validation_error(
       :invalid_type,
       "Killmails must be a list, got: #{inspect(invalid_killmails)}"
     )}
  end
end
