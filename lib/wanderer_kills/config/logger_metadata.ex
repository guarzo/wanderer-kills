defmodule WandererKills.Config.LoggerMetadata do
  @moduledoc """
  Centralized logger metadata configuration.
  
  This module provides a single source of truth for all logger metadata keys
  used throughout the application, avoiding duplication between config files.
  """

  @doc """
  Returns the complete list of logger metadata keys.
  
  This includes all metadata keys used throughout the application,
  organized by category for better maintainability.
  """
  def all_keys do
    standard_metadata() ++
    core_metadata() ++
    http_metadata() ++
    eve_metadata() ++
    cache_metadata() ++
    processing_metadata() ++
    websocket_metadata() ++
    retry_metadata() ++
    analysis_metadata() ++
    validation_metadata() ++
    subscription_metadata() ++
    pubsub_metadata()
  end

  @doc """
  Returns a subset of metadata keys suitable for development.
  
  This excludes some verbose fields like pid, application, and mfa
  for cleaner development logs.
  """
  def dev_keys do
    # Start with basic fields
    [:request_id, :file, :line] ++
    # Add all other categories
    core_metadata() ++
    http_metadata() ++
    eve_metadata() ++
    cache_metadata() ++
    processing_metadata() ++
    websocket_metadata() ++
    retry_metadata() ++
    analysis_metadata() ++
    validation_metadata() ++
    subscription_metadata() ++
    pubsub_metadata() ++
    # Additional dev-specific fields
    dev_specific_metadata()
  end

  # Standard Elixir metadata
  defp standard_metadata do
    [
      :request_id,
      :application,
      :module,
      :function,
      :line
    ]
  end

  # Core application metadata
  defp core_metadata do
    [
      :system_id,
      :killmail_id,
      :operation,
      :step,
      :status,
      :error,
      :duration,
      :source,
      :reason,
      :type,
      :message,
      :stacktrace,
      :timestamp,
      :kind
    ]
  end

  # HTTP and API metadata
  defp http_metadata do
    [
      :url,
      :response_time,
      :method,
      :service,
      :endpoint,
      :duration_ms,
      :response_size,
      :query_string,
      :remote_ip
    ]
  end

  # EVE Online entity metadata
  defp eve_metadata do
    [
      :character_id,
      :corporation_id,
      :alliance_id,
      :type_id,
      :solar_system_id,
      :ship_type_id,
      :victim_character,
      :victim_corp,
      :attacker_count,
      :total_value,
      :npc_kill
    ]
  end

  # Cache metadata
  defp cache_metadata do
    [
      :cache,
      :cache_key,
      :cache_type,
      :ttl,
      :namespace,
      :id
    ]
  end

  # Processing metadata
  defp processing_metadata do
    [
      :killmail_count,
      :count,
      :result,
      :data_source,
      :payload_size_bytes,
      :fresh_kills_fetched,
      :kills_to_process,
      :updates,
      :kills_processed,
      :kills_older,
      :kills_skipped,
      :legacy_kills,
      :no_kills_polls,
      :errors,
      :active_systems,
      :total_polls
    ]
  end

  # WebSocket and connection metadata
  defp websocket_metadata do
    [
      :systems,
      :active_connections,
      :kills_sent_realtime,
      :kills_sent_preload,
      :kills_per_minute,
      :connections_per_minute,
      :user_id,
      :subscription_id,
      :systems_count,
      :peer_data,
      :user_agent,
      :initial_systems_count,
      :new_systems_count,
      :total_systems_count,
      :removed_systems_count,
      :remaining_systems_count,
      :total_systems,
      :total_kills_sent,
      :limit,
      :total_cached_ids,
      :sample_ids,
      :requested_ids,
      :enriched_found,
      :enriched_missing,
      :failed_samples,
      :killmail_ids,
      :cached_ids_count,
      :subscribed_systems_count,
      :disconnect_reason,
      :connection_duration_seconds,
      :socket_transport
    ]
  end

  # Retry and timeout metadata
  defp retry_metadata do
    [
      :attempt,
      :max_attempts,
      :remaining_attempts,
      :delay_ms,
      :timeout,
      :request_type,
      :raw_count,
      :parsed_count,
      :enriched_count,
      :since_hours,
      :provided_id,
      :types,
      :groups,
      :file,
      :path,
      :pass_type,
      :hours,
      :limit,
      :max_concurrency,
      :purpose,
      :format,
      :percentage,
      :description,
      :unit,
      :value,
      :count,
      :total,
      :processed,
      :skipped,
      :error
    ]
  end

  # Analysis metadata
  defp analysis_metadata do
    [
      :total_killmails_analyzed,
      :format_distribution,
      :system_distribution,
      :ship_distribution,
      :character_distribution,
      :corporation_distribution,
      :alliance_distribution,
      :ship_type_distribution,
      :purpose,
      :sample_index,
      :sample_size,
      :sample_type,
      :sample_value,
      :sample_unit,
      :sample_structure,
      :data_type,
      :raw_keys,
      :has_full_data,
      :needs_esi_fetch,
      :byte_size,
      :tasks,
      :group_ids,
      :error_count,
      :total_groups,
      :success_count,
      :type_count
    ]
  end

  # Validation metadata
  defp validation_metadata do
    [
      :cutoff_time,
      :killmail_sample,
      :required_fields,
      :missing_fields,
      :available_keys,
      :raw_structure,
      :parsed_structure,
      :enriched_structure,
      :killmail_keys,
      :kill_count,
      :hash,
      :has_solar_system_id,
      :has_kill_count,
      :has_hash,
      :has_killmail_id,
      :has_system_id,
      :has_ship_type_id,
      :has_character_id,
      :has_victim,
      :has_attackers,
      :has_zkb,
      :parser_type,
      :killmail_hash,
      :recommendation,
      :structure,
      :kill_time,
      :kill_time_type,
      :kill_time_value,
      :cutoff
    ]
  end

  # Subscription metadata
  defp subscription_metadata do
    [
      :subscriber_id,
      :system_ids,
      :callback_url,
      :subscription_id,
      :status,
      :system_count,
      :has_callback,
      :total_subscriptions,
      :active_subscriptions,
      :removed_count,
      :requested_systems,
      :successful_systems,
      :failed_systems,
      :total_systems,
      :kills_count,
      :subscriber_count,
      :subscriber_ids,
      :via_pubsub,
      :via_webhook,
      :kills_type,
      :kills_value
    ]
  end

  # PubSub metadata
  defp pubsub_metadata do
    [
      :pubsub_name,
      :pubsub_topic,
      :pubsub_message,
      :pubsub_metadata,
      :pubsub_payload,
      :pubsub_headers,
      :pubsub_timestamp,
      :total_kills,
      :filtered_kills,
      :total_cached_kills,
      :cache_error,
      :returned_kills,
      :unexpected_response,
      :cached_count,
      :client_identifier,
      :unenriched_count,
      :kill_time_range
    ]
  end

  # Development-specific metadata (not in main config)
  defp dev_specific_metadata do
    []
  end
end