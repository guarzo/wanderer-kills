defmodule WandererKills.Core.ClientBehaviour do
  @moduledoc """
  Behaviour interface for WandererKills service clients.

  This behaviour defines the contract for interacting with zKillboard data,
  including fetching killmails, managing subscriptions, and accessing cached data.
  """

  @type killmail :: map()
  @type system_id :: integer()
  @type subscriber_id :: String.t()

  @doc """
  Fetches killmails for a specific system within the given time window.

  ## Parameters
  - system_id: The solar system ID to fetch kills for
  - since_hours: Number of hours to look back from now
  - limit: Maximum number of kills to return

  ## Returns
  - {:ok, [killmail()]} - List of killmail data
  - {:error, term()} - Error occurred during fetch
  """
  @callback fetch_system_killmails(
              system_id :: integer(),
              since_hours :: integer(),
              limit :: integer()
            ) ::
              {:ok, [killmail()]} | {:error, term()}

  @doc """
  Fetches killmails for multiple systems within the given time window.

  ## Parameters
  - system_ids: List of solar system IDs to fetch kills for
  - since_hours: Number of hours to look back from now
  - limit: Maximum number of kills to return per system

  ## Returns
  - {:ok, %{integer() => [killmail()]}} - Map of system_id to killmail lists
  - {:error, term()} - Error occurred during fetch
  """
  @callback fetch_systems_killmails(
              system_ids :: [integer()],
              since_hours :: integer(),
              limit :: integer()
            ) ::
              {:ok, %{integer() => [killmail()]}} | {:error, term()}

  @doc """
  Retrieves cached killmails for a specific system.

  ## Parameters
  - system_id: The solar system ID to get cached kills for

  ## Returns
  - [killmail()] - List of cached killmail data (empty list if none cached)
  """
  @callback fetch_cached_killmails(system_id :: integer()) :: [killmail()]

  @doc """
  Retrieves cached killmails for multiple systems.

  ## Parameters
  - system_ids: List of solar system IDs to get cached kills for

  ## Returns
  - %{integer() => [killmail()]} - Map of system_id to cached killmail lists
  """
  @callback fetch_cached_killmails_for_systems(system_ids :: [integer()]) :: %{
              integer() => [killmail()]
            }

  @doc """
  Subscribes to killmail updates for specified systems.

  ## Parameters
  - subscriber_id: Unique identifier for the subscriber
  - system_ids: List of system IDs to subscribe to
  - callback_url: Optional webhook URL for notifications (nil for PubSub only)

  ## Returns
  - {:ok, subscription_id} - Subscription created successfully
  - {:error, term()} - Error occurred during subscription
  """
  @callback subscribe_to_killmails(
              subscriber_id :: String.t(),
              system_ids :: [integer()],
              callback_url :: String.t() | nil
            ) ::
              {:ok, subscription_id :: String.t()} | {:error, term()}

  @doc """
  Unsubscribes from all killmail updates for a subscriber.

  ## Parameters
  - subscriber_id: Unique identifier for the subscriber to unsubscribe

  ## Returns
  - :ok - Successfully unsubscribed
  - {:error, term()} - Error occurred during unsubscription
  """
  @callback unsubscribe_from_killmails(subscriber_id :: String.t()) :: :ok | {:error, term()}

  @doc """
  Retrieves a specific killmail by ID.

  ## Parameters
  - killmail_id: The killmail ID to retrieve

  ## Returns
  - killmail() - The killmail data if found
  - nil - Killmail not found
  """
  @callback get_killmail(killmail_id :: integer()) :: killmail() | nil

  @doc """
  Gets the current kill count for a system.

  ## Parameters
  - system_id: The solar system ID to get kill count for

  ## Returns
  - integer() - Current kill count for the system
  """
  @callback get_system_killmail_count(system_id :: integer()) :: integer()
end
