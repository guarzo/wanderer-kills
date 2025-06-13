defmodule WandererKillsWeb.SubscriptionController do
  @moduledoc """
  HTTP API controller for managing killmail webhook subscriptions.

  Supports subscribing to killmails by:
  - System IDs - receive all kills in specified systems
  - Character IDs - receive kills where character is victim or attacker
  - Both - receive kills matching either criteria
  """

  use WandererKillsWeb, :controller

  alias WandererKills.SubscriptionManager
  alias WandererKills.Support.Error

  @doc """
  Create a new webhook subscription.

  ## Request body:
  ```json
  {
    "subscriber_id": "user123",
    "system_ids": [30000142, 30000143],
    "character_ids": [95465499, 90379338],
    "callback_url": "https://example.com/webhook"
  }
  ```

  At least one of system_ids or character_ids must be provided.
  """
  def create(conn, params) do
    with {:ok, attrs} <- validate_create_params(params),
         {:ok, subscription_id} <- SubscriptionManager.add_subscription(attrs) do
      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          subscription_id: subscription_id,
          message: "Subscription created successfully"
        }
      })
    else
      {:error, reason} ->
        message =
          case reason do
            %Error{} -> Error.to_string(reason)
            binary when is_binary(binary) -> binary
            _ -> inspect(reason)
          end

        conn
        |> put_status(:bad_request)
        |> json(%{
          error: %{
            message: message,
            details: reason
          }
        })
    end
  end

  @doc """
  List all active subscriptions.

  Returns an array of subscription objects.
  """
  def index(conn, _params) do
    subscriptions = SubscriptionManager.list_subscriptions()

    conn
    |> json(%{
      data: %{
        subscriptions: subscriptions,
        count: length(subscriptions)
      }
    })
  end

  @doc """
  Get subscription statistics.

  Returns counts and aggregate information about subscriptions.
  """
  def stats(conn, _params) do
    stats = SubscriptionManager.get_stats()

    conn
    |> json(%{
      data: stats
    })
  end

  @doc """
  Delete all subscriptions for a subscriber.

  Unsubscribes the subscriber from all killmail notifications.
  """
  def delete(conn, %{"subscriber_id" => subscriber_id}) do
    case SubscriptionManager.unsubscribe(subscriber_id) do
      :ok ->
        conn
        |> json(%{
          data: %{
            message: "Successfully unsubscribed",
            subscriber_id: subscriber_id
          }
        })

      {:error, reason} ->
        message =
          case reason do
            %Error{} -> Error.to_string(reason)
            binary when is_binary(binary) -> binary
            _ -> inspect(reason)
          end

        conn
        |> put_status(:bad_request)
        |> json(%{
          error: %{
            message: message,
            details: reason
          }
        })
    end
  end

  # Private functions

  defp validate_create_params(params) do
    attrs = %{
      "subscriber_id" => params["subscriber_id"],
      "system_ids" => normalize_ids(params["system_ids"]),
      "character_ids" => normalize_ids(params["character_ids"]),
      "callback_url" => params["callback_url"]
    }

    cond do
      is_nil(attrs["subscriber_id"]) or attrs["subscriber_id"] == "" ->
        {:error, "subscriber_id is required"}

      is_nil(attrs["callback_url"]) or attrs["callback_url"] == "" ->
        {:error, "callback_url is required"}

      not valid_url?(attrs["callback_url"]) ->
        {:error, "callback_url must be a valid HTTP/HTTPS URL"}

      Enum.empty?(attrs["system_ids"]) and Enum.empty?(attrs["character_ids"]) ->
        {:error, "At least one system_id or character_id is required"}

      not valid_ids?(attrs["system_ids"]) ->
        {:error, "system_ids must be an array of positive integers"}

      not valid_ids?(attrs["character_ids"]) ->
        {:error, "character_ids must be an array of positive integers"}

      length(attrs["system_ids"]) > 100 ->
        {:error, "Maximum 100 system_ids allowed per subscription"}

      length(attrs["character_ids"]) > 1000 ->
        {:error, "Maximum 1000 character_ids allowed per subscription"}

      true ->
        {:ok, attrs}
    end
  end

  defp normalize_ids(nil), do: []

  defp normalize_ids(ids) when is_list(ids) do
    ids
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_ids(_), do: []

  defp valid_ids?(ids) do
    is_list(ids) and Enum.all?(ids, fn id -> is_integer(id) and id > 0 end)
  end

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        true

      _ ->
        false
    end
  end
end
