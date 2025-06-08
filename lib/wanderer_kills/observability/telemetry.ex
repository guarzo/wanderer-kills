defmodule WandererKills.Observability.Telemetry do
  @moduledoc """
  Handles telemetry events for the WandererKills application.

  This module provides functionality to:
  - Execute telemetry events with helper functions
  - Attach and detach telemetry event handlers
  - Process telemetry events through handlers
  - Centralized logging of telemetry events

  ## Events

  Cache events:
  - `[:wanderer_kills, :cache, :hit]` - When a cache lookup succeeds
  - `[:wanderer_kills, :cache, :miss]` - When a cache lookup fails
  - `[:wanderer_kills, :cache, :error]` - When a cache operation fails

  HTTP events:
  - `[:wanderer_kills, :http, :request, :start]` - When an HTTP request starts
  - `[:wanderer_kills, :http, :request, :stop]` - When an HTTP request completes

  Fetch events:
  - `[:wanderer_kills, :fetch, :killmail, :success]` - When a killmail is successfully fetched
  - `[:wanderer_kills, :fetch, :killmail, :error]` - When a killmail fetch fails
  - `[:wanderer_kills, :fetch, :system, :complete]` - When a system fetch completes
  - `[:wanderer_kills, :fetch, :system, :error]` - When a system fetch fails

  Parser events:
  - `[:wanderer_kills, :parser, :stored]` - When killmails are stored
  - `[:wanderer_kills, :parser, :skipped]` - When killmails are skipped
  - `[:wanderer_kills, :parser, :summary]` - Parser summary statistics

  System events:
  - `[:wanderer_kills, :system, :memory]` - Memory usage metrics
  - `[:wanderer_kills, :system, :cpu]` - CPU usage metrics

  ## Usage

  ```elixir
  # Execute telemetry events using helper functions:
  Telemetry.http_request_start("GET", "https://api.example.com")
  Telemetry.fetch_system_complete(12345, :success)
  Telemetry.cache_hit("my_key")

  # Attach/detach handlers during application lifecycle
  Telemetry.attach_handlers()
  Telemetry.detach_handlers()
  ```

  ## Note

  Periodic measurements and metrics collection are handled by
  `WandererKills.Observability.Monitoring` module.
  """

  require Logger

  # -------------------------------------------------
  # Helper functions for telemetry execution
  # -------------------------------------------------

  @doc """
  Executes HTTP request start telemetry.
  """
  @spec http_request_start(String.t(), String.t()) :: :ok
  def http_request_start(method, url) do
    :telemetry.execute(
      [:wanderer_kills, :http, :request, :start],
      %{system_time: System.system_time(:native)},
      %{method: method, url: url}
    )
  end

  @doc """
  Executes HTTP request stop telemetry.
  """
  @spec http_request_stop(String.t(), String.t(), integer(), integer()) :: :ok
  def http_request_stop(method, url, duration, status_code) do
    :telemetry.execute(
      [:wanderer_kills, :http, :request, :stop],
      %{duration: duration},
      %{method: method, url: url, status_code: status_code}
    )
  end

  @doc """
  Executes HTTP request error telemetry.
  """
  @spec http_request_error(String.t(), String.t(), integer(), term()) :: :ok
  def http_request_error(method, url, duration, error) do
    :telemetry.execute(
      [:wanderer_kills, :http, :request, :stop],
      %{duration: duration},
      %{method: method, url: url, error: error}
    )
  end

  @doc """
  Executes fetch system start telemetry.
  """
  @spec fetch_system_start(integer(), integer(), atom()) :: :ok
  def fetch_system_start(system_id, limit, source) do
    :telemetry.execute(
      [:wanderer_kills, :fetch, :system, :start],
      %{system_id: system_id, limit: limit},
      %{source: source}
    )
  end

  @doc """
  Executes fetch system complete telemetry.
  """
  @spec fetch_system_complete(integer(), atom()) :: :ok
  def fetch_system_complete(system_id, result) do
    :telemetry.execute(
      [:wanderer_kills, :fetch, :system, :complete],
      %{system_id: system_id},
      %{result: result}
    )
  end

  @doc """
  Executes fetch system success telemetry.
  """
  @spec fetch_system_success(integer(), integer(), atom()) :: :ok
  def fetch_system_success(system_id, killmail_count, source) do
    :telemetry.execute(
      [:wanderer_kills, :fetch, :system, :success],
      %{system_id: system_id, killmail_count: killmail_count},
      %{source: source}
    )
  end

  @doc """
  Executes fetch system error telemetry.
  """
  @spec fetch_system_error(integer(), term(), atom()) :: :ok
  def fetch_system_error(system_id, error, source) do
    :telemetry.execute(
      [:wanderer_kills, :fetch, :system, :error],
      %{system_id: system_id},
      %{error: error, source: source}
    )
  end

  @doc """
  Executes cache hit telemetry.
  """
  @spec cache_hit(String.t()) :: :ok
  def cache_hit(key) do
    :telemetry.execute(
      [:wanderer_kills, :cache, :hit],
      %{},
      %{key: key}
    )
  end

  @doc """
  Executes cache miss telemetry.
  """
  @spec cache_miss(String.t()) :: :ok
  def cache_miss(key) do
    :telemetry.execute(
      [:wanderer_kills, :cache, :miss],
      %{},
      %{key: key}
    )
  end

  @doc """
  Executes cache error telemetry.
  """
  @spec cache_error(String.t(), term()) :: :ok
  def cache_error(key, reason) do
    :telemetry.execute(
      [:wanderer_kills, :cache, :error],
      %{},
      %{key: key, reason: reason}
    )
  end

  @doc """
  Executes parser telemetry.
  """
  @spec parser_stored(integer()) :: :ok
  def parser_stored(count \\ 1) do
    :telemetry.execute(
      [:wanderer_kills, :parser, :stored],
      %{count: count},
      %{}
    )
  end

  @doc """
  Executes parser skipped telemetry.
  """
  @spec parser_skipped(integer()) :: :ok
  def parser_skipped(count \\ 1) do
    :telemetry.execute(
      [:wanderer_kills, :parser, :skipped],
      %{count: count},
      %{}
    )
  end

  @doc """
  Executes parser summary telemetry.
  """
  @spec parser_summary(integer(), integer()) :: :ok
  def parser_summary(stored, skipped) do
    :telemetry.execute(
      [:wanderer_kills, :parser, :summary],
      %{stored: stored, skipped: skipped},
      %{}
    )
  end

  # -------------------------------------------------
  # Handler attachment/detachment functions
  # -------------------------------------------------

  @doc """
  Attaches telemetry event handlers for all application events.

  This should be called during application startup to ensure
  all telemetry events are properly logged and processed.
  """
  @spec attach_handlers() :: :ok
  def attach_handlers do
    # Cache hit/miss handlers
    :telemetry.attach_many(
      "wanderer-kills-cache-handler",
      [
        [:wanderer_kills, :cache, :hit],
        [:wanderer_kills, :cache, :miss],
        [:wanderer_kills, :cache, :error]
      ],
      &WandererKills.Observability.Telemetry.handle_cache_event/4,
      nil
    )

    # HTTP request handlers
    :telemetry.attach_many(
      "wanderer-kills-http-handler",
      [
        [:wanderer_kills, :http, :request, :start],
        [:wanderer_kills, :http, :request, :stop]
      ],
      &WandererKills.Observability.Telemetry.handle_http_event/4,
      nil
    )

    # Fetch handlers
    :telemetry.attach_many(
      "wanderer-kills-fetch-handler",
      [
        [:wanderer_kills, :fetch, :killmail, :success],
        [:wanderer_kills, :fetch, :killmail, :error],
        [:wanderer_kills, :fetch, :system, :start],
        [:wanderer_kills, :fetch, :system, :complete],
        [:wanderer_kills, :fetch, :system, :success],
        [:wanderer_kills, :fetch, :system, :error]
      ],
      &WandererKills.Observability.Telemetry.handle_fetch_event/4,
      nil
    )

    # Parser handlers
    :telemetry.attach_many(
      "wanderer-kills-parser-handler",
      [
        [:wanderer_kills, :parser, :stored],
        [:wanderer_kills, :parser, :skipped],
        [:wanderer_kills, :parser, :summary]
      ],
      &WandererKills.Observability.Telemetry.handle_parser_event/4,
      nil
    )

    # System metrics handlers
    :telemetry.attach_many(
      "wanderer-kills-system-handler",
      [
        [:wanderer_kills, :system, :memory],
        [:wanderer_kills, :system, :cpu]
      ],
      &WandererKills.Observability.Telemetry.handle_system_event/4,
      nil
    )

    :ok
  end

  @doc """
  Detaches all telemetry event handlers.

  This should be called during application shutdown to clean up
  telemetry handlers properly.
  """
  @spec detach_handlers() :: :ok
  def detach_handlers do
    :telemetry.detach("wanderer-kills-cache-handler")
    :telemetry.detach("wanderer-kills-http-handler")
    :telemetry.detach("wanderer-kills-fetch-handler")
    :telemetry.detach("wanderer-kills-parser-handler")
    :telemetry.detach("wanderer-kills-system-handler")
    :ok
  end

  # -------------------------------------------------
  # Event handlers
  # -------------------------------------------------

  @doc """
  Handles cache-related telemetry events.
  """
  def handle_cache_event([:wanderer_kills, :cache, event], _measurements, metadata, _config) do
    case event do
      :hit ->
        Logger.debug("[Cache] Hit for key: #{inspect(metadata.key)}")

      :miss ->
        Logger.debug("[Cache] Miss for key: #{inspect(metadata.key)}")

      :error ->
        Logger.error(
          "[Cache] Error for key: #{inspect(metadata.key)}, reason: #{inspect(metadata.reason)}"
        )
    end
  end

  @doc """
  Handles HTTP request telemetry events.
  """
  def handle_http_event(
        [:wanderer_kills, :http, :request, event],
        _measurements,
        metadata,
        _config
      ) do
    case event do
      :start ->
        Logger.debug("[HTTP] Starting request: #{metadata.method} #{metadata.url}")

      :stop ->
        case metadata do
          %{status_code: status} ->
            Logger.debug(
              "[HTTP] Completed request: #{metadata.method} #{metadata.url} (#{status})"
            )

          %{error: reason} ->
            Logger.error(
              "[HTTP] Failed request: #{metadata.method} #{metadata.url} (#{inspect(reason)})"
            )
        end
    end
  end

  @doc """
  Handles fetch operation telemetry events.
  """
  def handle_fetch_event([:wanderer_kills, :fetch, type, event], measurements, metadata, _config) do
    case {type, event} do
      {:killmail, :success} ->
        Logger.debug("[Fetch] Successfully fetched killmail: #{measurements.killmail_id}")

      {:killmail, :error} ->
        Logger.error(
          "[Fetch] Failed to fetch killmail: #{measurements.killmail_id}, reason: #{inspect(metadata.error)}"
        )

      {:system, :start} ->
        Logger.debug(
          "[Fetch] Starting system fetch: #{measurements.system_id} (limit: #{measurements.limit})"
        )

      {:system, :complete} ->
        Logger.debug(
          "[Fetch] Completed system fetch: #{measurements.system_id} (#{metadata.result})"
        )

      {:system, :success} ->
        Logger.debug(
          "[Fetch] Successful system fetch: #{measurements.system_id} (#{measurements.killmail_count} killmails)"
        )

      {:system, :error} ->
        Logger.error(
          "[Fetch] Failed system fetch: #{measurements.system_id}, reason: #{inspect(metadata.error)}"
        )
    end
  end

  @doc """
  Handles parser telemetry events.
  """
  def handle_parser_event([:wanderer_kills, :parser, event], measurements, _metadata, _config) do
    case event do
      :stored ->
        Logger.debug("[Parser] Stored #{measurements.count} killmails")

      :skipped ->
        Logger.debug("[Parser] Skipped #{measurements.count} killmails")

      :summary ->
        Logger.info(
          "[Parser] Summary - Stored: #{measurements.stored}, Skipped: #{measurements.skipped}"
        )
    end
  end

  @doc """
  Handles system resource telemetry events.
  """
  def handle_system_event([:wanderer_kills, :system, event], measurements, _metadata, _config) do
    case event do
      :memory ->
        Logger.debug(
          "[System] Memory usage - Total: #{measurements.total_memory}MB, Process: #{measurements.process_memory}MB"
        )

      :cpu ->
        # Safely handle the case where total_cpu might not be present
        case Map.get(measurements, :total_cpu) do
          nil ->
            # If total_cpu is not available, log the available metrics
            Logger.debug(
              "[System] System metrics - Processes: #{measurements.process_count}, Ports: #{measurements.port_count}, Schedulers: #{measurements.schedulers}, Run Queue: #{measurements.run_queue}"
            )

          total_cpu ->
            # Log with total_cpu and process_cpu if available
            process_cpu = Map.get(measurements, :process_cpu, "N/A")
            Logger.debug("[System] CPU usage - Total: #{total_cpu}%, Process: #{process_cpu}%")
        end
    end
  end
end
