defmodule WandererKills.Telemetry do

@moduledoc """
  Telemetry event handlers for monitoring application metrics.
  """

  require Logger

  def setup do
    # KillmailStore metrics
    :telemetry.attach_many(
      "wanderer-kills-killmail-store-handler",
      [
        [:wanderer_kills, :killmail_store, :insert],
        [:wanderer_kills, :killmail_store, :fetch],
        [:wanderer_kills, :killmail_store, :fetch_one],
        [:wanderer_kills, :killmail_store, :gc]
      ],
      &handle_killmail_store_event/4,
      nil
    )

    # Cache metrics
    :telemetry.attach_many(
      "wanderer-kills-cache-handler",
      [
        [:wanderer_kills, :cache, :get],
        [:wanderer_kills, :cache, :put],
        [:wanderer_kills, :cache, :delete],
        [:wanderer_kills, :cache, :expire]
      ],
      &handle_cache_event/4,
      nil
    )

    # HTTP metrics
    :telemetry.attach_many(
      "wanderer-kills-http-handler",
      [
        [:wanderer_kills, :http, :request],
        [:wanderer_kills, :http, :retry],
        [:wanderer_kills, :http, :error]
      ],
      &handle_http_event/4,
      nil
    )

    # Circuit breaker metrics
    :telemetry.attach_many(
      "wanderer-kills-circuit-breaker-handler",
      [
        [:wanderer_kills, :circuit_breaker, :trip],
        [:wanderer_kills, :circuit_breaker, :reset],
        [:wanderer_kills, :circuit_breaker, :reject]
      ],
      &handle_circuit_breaker_event/4,
      nil
    )

    # API metrics
    :telemetry.attach_many(
      "wanderer-kills-api-handler",
      [
        [:wanderer_kills, :api, :request],
        [:wanderer_kills, :api, :error],
        [:wanderer_kills, :api, :validation_error]
      ],
      &handle_api_event/4,
      nil
    )
  end

  # KillmailStore event handlers
  defp handle_killmail_store_event(
         [:wanderer_kills, :killmail_store, :insert],
         measurements,
         metadata,
         _config
       ) do
    Logger.metadata(
      operation: :killmail_store_insert,
      system_id: metadata.system_id,
      event_count: measurements.event_count
    )

    Logger.info("Inserted killmail events", %{
      system_id: metadata.system_id,
      event_count: measurements.event_count,
      duration_ms: measurements.duration
    })
  end

  defp handle_killmail_store_event(
         [:wanderer_kills, :killmail_store, :fetch],
         measurements,
         metadata,
         _config
       ) do
    Logger.metadata(
      operation: :killmail_store_fetch,
      client_id: metadata.client_id,
      system_count: length(metadata.system_ids)
    )

    Logger.info("Fetched killmail events", %{
      client_id: metadata.client_id,
      system_count: length(metadata.system_ids),
      event_count: measurements.event_count,
      duration_ms: measurements.duration
    })
  end

  defp handle_killmail_store_event(
         [:wanderer_kills, :killmail_store, :fetch_one],
         measurements,
         metadata,
         _config
       ) do
    Logger.metadata(
      operation: :killmail_store_fetch_one,
      client_id: metadata.client_id,
      system_count: length(metadata.system_ids)
    )

    Logger.info("Fetched single killmail event", %{
      client_id: metadata.client_id,
      system_count: length(metadata.system_ids),
      duration_ms: measurements.duration
    })
  end

  defp handle_killmail_store_event(
         [:wanderer_kills, :killmail_store, :gc],
         measurements,
         metadata,
         _config
       ) do
    Logger.metadata(
      operation: :killmail_store_gc,
      system_count: length(metadata.systems)
    )

    Logger.info("Garbage collected killmail events", %{
      system_count: length(metadata.systems),
      deleted_count: measurements.deleted_count,
      duration_ms: measurements.duration
    })
  end

  # Cache event handlers
  defp handle_cache_event([:wanderer_kills, :cache, :get], measurements, metadata, _config) do
    Logger.metadata(
      operation: :cache_get,
      cache: metadata.cache,
      key: metadata.key
    )

    Logger.debug("Cache get operation", %{
      cache: metadata.cache,
      key: metadata.key,
      hit: measurements.hit,
      duration_ms: measurements.duration
    })
  end

  defp handle_cache_event([:wanderer_kills, :cache, :put], measurements, metadata, _config) do
    Logger.metadata(
      operation: :cache_put,
      cache: metadata.cache,
      key: metadata.key
    )

    Logger.debug("Cache put operation", %{
      cache: metadata.cache,
      key: metadata.key,
      ttl: metadata.ttl,
      duration_ms: measurements.duration
    })
  end

  defp handle_cache_event([:wanderer_kills, :cache, :delete], measurements, metadata, _config) do
    Logger.metadata(
      operation: :cache_delete,
      cache: metadata.cache,
      key: metadata.key
    )

    Logger.debug("Cache delete operation", %{
      cache: metadata.cache,
      key: metadata.key,
      duration_ms: measurements.duration
    })
  end

  defp handle_cache_event([:wanderer_kills, :cache, :expire], measurements, metadata, _config) do
    Logger.metadata(
      operation: :cache_expire,
      cache: metadata.cache
    )

    Logger.debug("Cache expire operation", %{
      cache: metadata.cache,
      expired_count: measurements.expired_count,
      duration_ms: measurements.duration
    })
  end

  # HTTP event handlers
  defp handle_http_event([:wanderer_kills, :http, :request], measurements, metadata, _config) do
    Logger.metadata(
      operation: :http_request,
      method: metadata.method,
      url: metadata.url
    )

    Logger.info("HTTP request", %{
      method: metadata.method,
      url: metadata.url,
      status: measurements.status,
      duration_ms: measurements.duration
    })
  end

  defp handle_http_event([:wanderer_kills, :http, :retry], measurements, metadata, _config) do
    Logger.metadata(
      operation: :http_retry,
      method: metadata.method,
      url: metadata.url
    )

    Logger.warning("HTTP request retry", %{
      method: metadata.method,
      url: metadata.url,
      attempt: measurements.attempt,
      max_attempts: measurements.max_attempts,
      duration_ms: measurements.duration
    })
  end

  defp handle_http_event([:wanderer_kills, :http, :error], measurements, metadata, _config) do
    Logger.metadata(
      operation: :http_error,
      method: metadata.method,
      url: metadata.url
    )

    Logger.error("HTTP request error", %{
      method: metadata.method,
      url: metadata.url,
      status: measurements.status,
      error: measurements.error,
      duration_ms: measurements.duration
    })
  end

  # Circuit breaker event handlers
  defp handle_circuit_breaker_event(
         [:wanderer_kills, :circuit_breaker, :trip],
         measurements,
         metadata,
         _config
       ) do
    Logger.metadata(
      operation: :circuit_breaker_trip,
      service: metadata.service
    )

    Logger.warning("Circuit breaker tripped", %{
      service: metadata.service,
      failure_count: measurements.failure_count,
      threshold: measurements.threshold,
      duration_ms: measurements.duration
    })
  end

  defp handle_circuit_breaker_event(
         [:wanderer_kills, :circuit_breaker, :reset],
         measurements,
         metadata,
         _config
       ) do
    Logger.metadata(
      operation: :circuit_breaker_reset,
      service: metadata.service
    )

    Logger.info("Circuit breaker reset", %{
      service: metadata.service,
      duration_ms: measurements.duration
    })
  end

  defp handle_circuit_breaker_event(
         [:wanderer_kills, :circuit_breaker, :reject],
         measurements,
         metadata,
         _config
       ) do
    Logger.metadata(
      operation: :circuit_breaker_reject,
      service: metadata.service
    )

    Logger.warning("Circuit breaker rejected request", %{
      service: metadata.service,
      duration_ms: measurements.duration
    })
  end

  # API event handlers
  defp handle_api_event([:wanderer_kills, :api, :request], measurements, metadata, _config) do
    Logger.metadata(
      operation: :api_request,
      endpoint: metadata.endpoint,
      client_id: metadata.client_id
    )

    Logger.info("API request", %{
      endpoint: metadata.endpoint,
      client_id: metadata.client_id,
      status: measurements.status,
      duration_ms: measurements.duration
    })
  end

  defp handle_api_event([:wanderer_kills, :api, :error], measurements, metadata, _config) do
    Logger.metadata(
      operation: :api_error,
      endpoint: metadata.endpoint,
      client_id: metadata.client_id
    )

    Logger.error("API error", %{
      endpoint: metadata.endpoint,
      client_id: metadata.client_id,
      error: measurements.error,
      duration_ms: measurements.duration
    })
  end

  defp handle_api_event(
         [:wanderer_kills, :api, :validation_error],
         measurements,
         metadata,
         _config
       ) do
    Logger.metadata(
      operation: :api_validation_error,
      endpoint: metadata.endpoint,
      client_id: metadata.client_id
    )

    Logger.warning("API validation error", %{
      endpoint: metadata.endpoint,
      client_id: metadata.client_id,
      error: measurements.error,
      duration_ms: measurements.duration
    })
  end
end
