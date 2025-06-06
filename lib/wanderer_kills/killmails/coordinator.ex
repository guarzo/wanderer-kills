defmodule WandererKills.Killmails.Coordinator do
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
  - `{:error, reason}` - On failure
  """

  require Logger
  alias WandererKills.Parser.Core

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
  - `{:error, reason}` - On failure

  ## Examples

  ```elixir
  # Parse a full killmail
  full = %{"killmail_id" => 12345, "victim" => %{...}}
  partial = %{"zkb" => %{"hash" => "abc123"}}
  cutoff = Clock.now()

  {:ok, enriched} = parse_full_and_store(full, partial, cutoff)

  # Handle invalid format
  {:error, :invalid_format} = parse_full_and_store(invalid_data, invalid_data, cutoff)
  ```
  """
  @spec parse_full_and_store(killmail(), killmail(), DateTime.t()) ::
          {:ok, killmail()} | {:ok, :kill_older} | {:error, term()}
  def parse_full_and_store(full, %{"zkb" => zkb}, cutoff) when is_map(full) do
    Logger.info("Starting to parse and store killmail", %{
      killmail_id: full["killmail_id"],
      operation: :parse_full_and_store,
      step: :start
    })

    process_killmail(full, zkb, cutoff)
  end

  def parse_full_and_store(_, _, _), do: {:error, :invalid_format}

  @spec process_killmail(killmail(), map(), DateTime.t()) ::
          {:ok, killmail()} | {:ok, :kill_older} | {:error, term()}
  defp process_killmail(full, zkb, cutoff) do
    with {:ok, merged} <- Core.merge_killmail_data(full, %{"zkb" => zkb}),
         {:ok, built} <- Core.build_kill_data(merged, cutoff),
         {:ok, enriched} <- enrich_killmail(built) do
      # Get system_id with nil check
      system_id = enriched["solar_system_id"] || enriched["system_id"]

      if system_id do
        # Make insert_event asynchronous using Task
        Task.start(fn ->
          try do
            :ok = WandererKills.Data.Stores.KillmailStore.insert_event(system_id, enriched)

            Logger.info("Successfully enriched and stored killmail", %{
              killmail_id: full["killmail_id"],
              system_id: system_id,
              operation: :process_killmail,
              status: :success
            })
          rescue
            error ->
              Logger.error("Failed to store killmail", %{
                killmail_id: full["killmail_id"],
                system_id: system_id,
                operation: :process_killmail,
                error: Exception.message(error),
                stacktrace: Exception.format_stacktrace(__STACKTRACE__),
                status: :error
              })
          end
        end)

        {:ok, enriched}
      else
        Logger.error("Missing system_id in enriched killmail", %{
          killmail_id: full["killmail_id"],
          operation: :process_killmail,
          status: :error
        })

        {:error, :missing_system_id}
      end
    else
      :older ->
        Logger.debug("Killmail is older than cutoff", %{
          killmail_id: full["killmail_id"],
          operation: :process_killmail,
          status: :kill_older
        })

        {:ok, :kill_older}

      {:error, reason} ->
        Logger.error("Failed to process killmail", %{
          killmail_id: full["killmail_id"],
          operation: :process_killmail,
          error: reason,
          status: :error
        })

        {:error, reason}
    end
  end

  @spec enrich_killmail(killmail()) :: {:ok, killmail()} | {:error, term()}
  defp enrich_killmail(killmail) do
    WandererKills.Parser.Enricher.enrich_killmail(killmail)
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
  - `{:error, reason}` - On failure

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
  {:error, :invalid_format} = parse_partial(invalid_data, cutoff)
  ```
  """
  @spec parse_partial(raw_killmail(), DateTime.t()) ::
          {:ok, killmail()} | {:ok, :kill_skipped} | :older | {:error, term()}
  def parse_partial(%{"killID" => id, "zkb" => %{"hash" => hash}} = partial, cutoff) do
    Logger.info("Starting to parse partial killmail", %{
      killmail_id: id,
      operation: :parse_partial,
      step: :start
    })

    case WandererKills.Cache.Specialized.EsiCache.get_killmail(id, hash) do
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

  def parse_partial(_, _), do: {:error, :invalid_format}
end
