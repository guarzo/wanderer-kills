defmodule WandererKills.Subscriptions.WebhookNotifier do
  @moduledoc """
  Handles webhook notifications for killmail subscriptions.

  This module is responsible for sending killmail updates to
  subscriber webhooks via HTTP POST requests.
  """

  require Logger
  alias WandererKills.Http.ClientProvider

  @webhook_timeout 10_000

  @doc """
  Sends a killmail update notification to a webhook URL.

  ## Parameters
  - `webhook_url` - The URL to send the notification to
  - `system_id` - The system ID for the kills
  - `kills` - List of killmail data
  - `subscription_id` - The subscription ID for logging

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec notify_webhook(String.t(), integer(), list(map()), String.t()) :: :ok | {:error, term()}
  def notify_webhook(webhook_url, system_id, kills, subscription_id) do
    # Validate webhook URL
    case validate_webhook_url(webhook_url) do
      :ok ->
        payload = build_webhook_payload(system_id, kills)

        Logger.info("🔔 Sending webhook notification",
          subscription_id: subscription_id,
          url: webhook_url,
          system_id: system_id,
          kill_count: length(kills)
        )

        case send_webhook_request(webhook_url, payload) do
          {:ok, _response} ->
            Logger.info("✅ Webhook notification sent successfully",
              subscription_id: subscription_id,
              url: webhook_url
            )

            :ok

          {:error, reason} ->
            Logger.error("❌ Failed to send webhook notification",
              subscription_id: subscription_id,
              url: webhook_url,
              error: inspect(reason)
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Invalid webhook URL",
          subscription_id: subscription_id,
          url: webhook_url,
          reason: reason
        )
        
        :ok
    end
  end

  @doc """
  Sends a killmail count update notification to a webhook URL.

  ## Parameters
  - `webhook_url` - The URL to send the notification to
  - `system_id` - The system ID for the count
  - `count` - Number of killmails
  - `subscription_id` - The subscription ID for logging

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec notify_webhook_count(String.t(), integer(), integer(), String.t()) ::
          :ok | {:error, term()}
  def notify_webhook_count(webhook_url, system_id, count, subscription_id) do
    # Validate webhook URL
    case validate_webhook_url(webhook_url) do
      :ok ->
        payload = build_count_payload(system_id, count)

        Logger.info("📊 Sending webhook count notification",
          subscription_id: subscription_id,
          url: webhook_url,
          system_id: system_id,
          count: count
        )

        case send_webhook_request(webhook_url, payload) do
          {:ok, _response} ->
            Logger.info("✅ Webhook count notification sent successfully",
              subscription_id: subscription_id,
              url: webhook_url
            )

            :ok

          {:error, reason} ->
            Logger.error("❌ Failed to send webhook count notification",
              subscription_id: subscription_id,
              url: webhook_url,
              error: inspect(reason)
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Invalid webhook URL for count notification",
          subscription_id: subscription_id,
          url: webhook_url,
          reason: reason
        )
        
        :ok
    end
  end

  # Private Functions

  defp build_webhook_payload(system_id, kills) do
    %{
      type: "killmail_update",
      system_id: system_id,
      kills: kills,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build_count_payload(system_id, count) do
    %{
      type: "killmail_count_update",
      system_id: system_id,
      count: count,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp send_webhook_request(url, payload) do
    headers = [
      {"Content-Type", "application/json"},
      {"User-Agent", "WandererKills/1.0"}
    ]

    client = ClientProvider.get_client()
    client.post(url, payload, headers: headers, timeout: @webhook_timeout)
  end

  defp validate_webhook_url(nil), do: {:error, :missing_url}
  defp validate_webhook_url(""), do: {:error, :empty_url}
  defp validate_webhook_url(_url), do: :ok
end
