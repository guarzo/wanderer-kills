defmodule WandererKills.Ingest.Killmails.Pipeline.Parser do
  @moduledoc """
  Core killmail parsing functionality with a focused API.

  This module provides the essential killmail parsing operations while keeping
  internal implementation details private. It follows a consistent naming
  convention and minimizes the public API surface.

  ## Public API

  - `parse_full_killmail/2` - Parse a complete killmail with zkb data
  - `parse_partial_killmail/2` - Parse a partial killmail, fetching full data
  - `merge_killmail_data/2` - Merge ESI and zKB data
  - `validate_killmail_time/1` - Validate killmail timestamp

  ## Usage

  ```elixir
  # Parse a complete killmail
  {:ok, parsed} = KillmailParser.parse_full_killmail(killmail, cutoff_time)

  # Parse a partial killmail
  {:ok, parsed} = KillmailParser.parse_partial_killmail(partial, cutoff_time)

  # Merge ESI and zKB data
  {:ok, merged} = KillmailParser.merge_killmail_data(esi_data, zkb_data)
  ```

  ## Error Handling

  All functions return standardized results:
  - `{:ok, result}` - On success
  - `{:ok, :kill_older}` - When killmail is older than cutoff
  - `{:error, reason}` - On failure
  """

  require Logger

  alias WandererKills.Core.Support.Error

  alias WandererKills.Ingest.Killmails.Pipeline.{
    Enricher,
    Validator,
    DataBuilder,
    ESIFetcher
  }

  alias WandererKills.Ingest.Killmails.Transformations

  @type killmail :: map()
  @type raw_killmail :: map()
  @type merged_killmail :: map()
  @type parse_result :: {:ok, killmail()} | {:ok, :kill_older} | {:error, term()}

  @doc """
  Parses a complete killmail with zkb data.

  This is the main entry point for parsing killmails when you have both
  the full ESI data and zKB metadata.

  ## Parameters
  - `killmail` - The merged killmail data (ESI + zKB)
  - `cutoff_time` - DateTime cutoff for filtering old killmails

  ## Returns
  - `{:ok, parsed_killmail}` - On successful parsing
  - `{:ok, :kill_older}` - When killmail is older than cutoff
  - `{:error, reason}` - On failure
  """
  @spec parse_full_killmail(killmail(), DateTime.t()) :: parse_result()
  def parse_full_killmail(killmail, cutoff_time) when is_map(killmail) do
    # Normalize field names first
    killmail = Transformations.normalize_field_names(killmail)
    killmail_id = Transformations.get_killmail_id(killmail)

    Logger.debug("Parsing full killmail",
      killmail_id: killmail_id,
      has_solar_system_id: Map.has_key?(killmail, "solar_system_id"),
      has_victim: Map.has_key?(killmail, "victim"),
      has_attackers: Map.has_key?(killmail, "attackers"),
      has_zkb: Map.has_key?(killmail, "zkb"),
      killmail_keys: Map.keys(killmail) |> Enum.sort()
    )

    with {:ok, validated} <- Validator.validate_killmail(killmail, cutoff_time),
         {:ok, built} <- DataBuilder.build_killmail_data(validated),
         {:ok, enriched} <- enrich_killmail_data(built) do
      {:ok, enriched}
    else
      {:error, %WandererKills.Core.Support.Error{type: :kill_too_old}} ->
        {:ok, :kill_older}

      {:error, reason} ->
        Logger.error("Failed to parse killmail",
          killmail_id: Transformations.get_killmail_id(killmail),
          error: reason,
          step: Validator.determine_failure_step(reason),
          killmail_sample: inspect(killmail, limit: 3, printable_limit: 100)
        )

        {:error, reason}
    end
  end

  @doc """
  Parses a partial killmail by fetching full data from ESI.

  ## Parameters
  - `partial` - The partial killmail data with zKB metadata
  - `cutoff_time` - DateTime cutoff for filtering old killmails

  ## Returns
  - `{:ok, parsed_killmail}` - On successful parsing
  - `{:ok, :kill_older}` - When killmail is older than cutoff
  - `{:error, reason}` - On failure
  """
  @spec parse_partial_killmail(raw_killmail(), DateTime.t()) :: parse_result()
  def parse_partial_killmail(partial, cutoff_time) do
    # Normalize field names first
    normalized = Transformations.normalize_field_names(partial)

    case {normalized["killmail_id"], normalized["zkb"]} do
      {id, zkb} when is_integer(id) and is_map(zkb) ->
        Logger.debug("Parsing partial killmail", killmail_id: id)

        with {:ok, full_data} <- ESIFetcher.fetch_full_killmail(id, zkb),
             {:ok, merged} <- DataBuilder.merge_killmail_data(full_data, normalized) do
          parse_full_killmail(merged, cutoff_time)
        else
          {:error, reason} ->
            Logger.error("Failed to parse partial killmail", killmail_id: id, error: reason)
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

  @doc """
  Merges ESI killmail data with zKB metadata.

  ## Parameters
  - `esi_data` - Full killmail data from ESI
  - `zkb_data` - Partial data with zKB metadata

  ## Returns
  - `{:ok, merged_killmail}` - On successful merge
  - `{:error, reason}` - On failure
  """
  @spec merge_killmail_data(killmail(), raw_killmail()) ::
          {:ok, merged_killmail()} | {:error, term()}
  def merge_killmail_data(esi_data, zkb_data) do
    DataBuilder.merge_killmail_data(esi_data, zkb_data)
  end

  # Private functions for internal implementation

  @spec enrich_killmail_data(killmail()) :: {:ok, killmail()} | {:error, term()}
  defp enrich_killmail_data(killmail) do
    case Enricher.enrich_killmail(killmail) do
      {:ok, enriched} ->
        # Store in cache after successful enrichment
        ESIFetcher.cache_enriched_killmail(enriched)
        {:ok, enriched}

      {:error, reason} ->
        Logger.warning("Failed to enrich killmail, using basic data",
          killmail_id: killmail["killmail_id"],
          error: reason
        )

        # Store basic data even if enrichment fails
        ESIFetcher.cache_enriched_killmail(killmail)
        {:ok, killmail}
    end
  end
end
