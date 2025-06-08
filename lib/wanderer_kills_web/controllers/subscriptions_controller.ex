defmodule WandererKillsWeb.SubscriptionsController do
  @moduledoc """
  Controller for subscription management endpoints.

  This controller provides endpoints for creating and managing kill subscriptions
  as specified in the WandererKills API interface.
  """

  import WandererKillsWeb.Api.Helpers
  require Logger
  alias WandererKills.Client

  def init(opts), do: opts

  @doc """
  Creates a new kill subscription.

  POST /api/v1/subscriptions
  Body: {"subscriber_id": "string", "system_ids": [int], "callback_url": "string"}
  """
  def create(conn, params) do
    with {:ok, subscriber_id} <- validate_subscriber_id(Map.get(params, "subscriber_id")),
         {:ok, system_ids} <- validate_system_ids(Map.get(params, "system_ids")),
         {:ok, callback_url} <- validate_callback_url(Map.get(params, "callback_url")) do
      Logger.info("Creating kill subscription",
        subscriber_id: subscriber_id,
        system_count: length(system_ids),
        has_callback: !is_nil(callback_url)
      )

      case Client.subscribe_to_kills(subscriber_id, system_ids, callback_url) do
        {:ok, subscription_id} ->
          response = %{
            subscription_id: subscription_id,
            status: "active",
            error: nil
          }

          render_success(conn, response)

        {:error, reason} ->
          Logger.error("Failed to create subscription",
            subscriber_id: subscriber_id,
            error: reason
          )

          render_error(conn, 500, "Failed to create subscription", "SUBSCRIPTION_ERROR", %{
            reason: inspect(reason)
          })
      end
    else
      {:error, :invalid_subscriber_id} ->
        render_error(conn, 400, "Invalid subscriber ID", "INVALID_SUBSCRIBER_ID")

      {:error, :invalid_system_ids} ->
        render_error(conn, 400, "Invalid system IDs", "INVALID_SYSTEM_IDS")

      {:error, :invalid_callback_url} ->
        render_error(conn, 400, "Invalid callback URL", "INVALID_CALLBACK_URL")
    end
  end

  @doc """
  Deletes a kill subscription.

  DELETE /api/v1/subscriptions/:subscriber_id
  """
  def delete(conn, %{"subscriber_id" => subscriber_id}) do
    case validate_subscriber_id(subscriber_id) do
      {:ok, validated_subscriber_id} ->
        Logger.info("Deleting kill subscription", subscriber_id: validated_subscriber_id)

        case Client.unsubscribe_from_kills(validated_subscriber_id) do
          :ok ->
            response = %{
              status: "deleted",
              error: nil
            }

            render_success(conn, response)

          {:error, :not_found} ->
            render_error(conn, 404, "Subscription not found", "NOT_FOUND")

          {:error, reason} ->
            Logger.error("Failed to delete subscription",
              subscriber_id: validated_subscriber_id,
              error: reason
            )

            render_error(conn, 500, "Failed to delete subscription", "SUBSCRIPTION_ERROR", %{
              reason: inspect(reason)
            })
        end

      {:error, :invalid_subscriber_id} ->
        render_error(conn, 400, "Invalid subscriber ID", "INVALID_SUBSCRIBER_ID")
    end
  end

  @doc """
  Lists all active subscriptions (for administrative purposes).

  GET /api/v1/subscriptions
  """
  def index(conn, _params) do
    Logger.debug("Listing all active subscriptions")

    subscriptions = Client.list_subscriptions()

    # Transform subscriptions for API response
    formatted_subscriptions =
      Enum.map(subscriptions, fn subscription ->
        %{
          subscriber_id: subscription.subscriber_id,
          system_ids: subscription.system_ids,
          created_at: DateTime.to_iso8601(subscription.created_at)
        }
      end)

    response = %{
      subscriptions: formatted_subscriptions
    }

    render_success(conn, response)
  end
end
