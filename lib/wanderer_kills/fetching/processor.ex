defmodule WandererKills.Fetching.Processor do
  @moduledoc """
  Killmail processing service.

  This module handles the parsing and enrichment of killmail data.
  It focuses solely on data transformation without API or cache interactions.
  """

  require Logger
  alias WandererKills.Killmails.{Parser, Enricher}
  alias WandererKills.Core.Error

  @type killmail :: map()
  @type system_id :: pos_integer()

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

  ## Examples

  ```elixir
  {:ok, processed} = Processor.process_killmails(raw_killmails, 30000142, 24)
  {:error, reason} = Processor.process_killmails(invalid_data, 30000142, 24)
  ```
  """
  @spec process_killmails([map()], system_id(), pos_integer()) ::
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
  Parses raw killmails with time filtering.

  ## Parameters
  - `raw_killmails` - List of raw killmail data
  - `since_hours` - Only include killmails newer than this many hours

  ## Returns
  - `{:ok, [parsed_killmail]}` - On successful parsing
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, parsed} = Processor.parse_killmails(raw_killmails, 24)
  ```
  """
  @spec parse_killmails([map()], pos_integer()) :: {:ok, [killmail()]} | {:error, term()}
  def parse_killmails(raw_killmails, since_hours)
      when is_list(raw_killmails) and is_integer(since_hours) do
    try do
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

  ## Parameters
  - `parsed_killmails` - List of parsed killmail data
  - `system_id` - The system ID (used for logging)

  ## Returns
  - `{:ok, [enriched_killmail]}` - On successful enrichment
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, enriched} = Processor.enrich_killmails(parsed_killmails, 30000142)
  ```
  """
  @spec enrich_killmails([killmail()], system_id()) :: {:ok, [killmail()]} | {:error, term()}
  def enrich_killmails(parsed_killmails, system_id)
      when is_list(parsed_killmails) and is_integer(system_id) do
    try do
      Logger.debug("Enriching killmails",
        system_id: system_id,
        parsed_count: length(parsed_killmails),
        operation: :enrich_killmails,
        step: :start
      )

      enriched =
        parsed_killmails
        |> Enum.map(fn killmail ->
          case Enricher.enrich_killmail(killmail) do
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
  end

  def enrich_killmails(invalid_killmails, _system_id) do
    {:error,
     Error.validation_error(
       :invalid_type,
       "Killmails must be a list, got: #{inspect(invalid_killmails)}"
     )}
  end

  @doc """
  Validates killmail time against a cutoff.

  ## Parameters
  - `killmail` - The killmail to validate
  - `cutoff` - The DateTime cutoff

  ## Returns
  - `true` - If killmail is newer than cutoff
  - `false` - If killmail is older than cutoff

  ## Examples

  ```elixir
  true = Processor.validate_killmail_time(killmail, ~U[2023-01-01 00:00:00Z])
  ```
  """
  @spec validate_killmail_time(killmail(), DateTime.t()) :: boolean()
  def validate_killmail_time(killmail, cutoff) when is_map(killmail) do
    kill_time_str = get_kill_time_field(killmail)

    case DateTime.from_iso8601(kill_time_str) do
      {:ok, kill_time, _offset} ->
        DateTime.compare(kill_time, cutoff) == :gt

      {:error, _reason} ->
        # If we can't parse the time, default to false (exclude it)
        false
    end
  end

  def validate_killmail_time(_invalid_killmail, _cutoff), do: false

  @doc """
  Processes a single killmail (for individual killmail fetching).

  ## Parameters
  - `killmail` - The raw killmail data
  - `enrich` - Whether to enrich the killmail (default: true)

  ## Returns
  - `{:ok, processed_killmail}` - On successful processing
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  {:ok, processed} = Processor.process_single_killmail(raw_killmail)
  {:ok, processed} = Processor.process_single_killmail(raw_killmail, false)
  ```
  """
  @spec process_single_killmail(map(), boolean()) :: {:ok, killmail()} | {:error, term()}
  def process_single_killmail(killmail, enrich \\ true)

  def process_single_killmail(killmail, enrich) when is_map(killmail) do
    try do
      # For single killmails, use a very permissive cutoff (1 year ago)
      _cutoff_time = DateTime.utc_now() |> DateTime.add(-365 * 24 * 60 * 60, :second)

      Logger.debug("Processing single killmail",
        killmail_id: Map.get(killmail, "killmail_id"),
        enrich: enrich,
        operation: :process_single_killmail,
        step: :start
      )

      case parse_killmails([killmail], 365 * 24) do
        {:ok, [parsed]} ->
          if enrich do
            case Enricher.enrich_killmail(parsed) do
              {:ok, enriched} -> {:ok, enriched}
              # Use basic data on enrichment failure
              {:error, _reason} -> {:ok, parsed}
            end
          else
            {:ok, parsed}
          end

        {:ok, []} ->
          {:error, Error.parsing_error(:no_results, "Killmail parsing produced no results")}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception during single killmail processing",
          killmail_id: Map.get(killmail, "killmail_id"),
          error: inspect(error),
          operation: :process_single_killmail,
          step: :exception
        )

        {:error, Error.parsing_error(:exception, "Exception during single killmail processing")}
    end
  end

  def process_single_killmail(invalid_killmail, _enrich) do
    {:error,
     Error.validation_error(
       :invalid_type,
       "Killmail must be a map, got: #{inspect(invalid_killmail)}"
     )}
  end

  # Private helper functions

  @spec get_kill_time_field(killmail()) :: String.t() | nil
  defp get_kill_time_field(killmail) do
    killmail["kill_time"] || killmail["killmail_time"]
  end
end
