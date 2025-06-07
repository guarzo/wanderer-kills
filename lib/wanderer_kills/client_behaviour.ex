defmodule WandererKills.ClientBehaviour do
  @moduledoc """
  Behaviour interface for WandererKills service clients.

  This behaviour defines the contract for interacting with zKillboard data,
  including fetching killmails, managing subscriptions, and accessing cached data.
  """

  @type kill :: map()
  @type system_id :: integer()
  @type subscriber_id :: String.t()

  @doc """
  Fetches killmails for a specific system within the given time window.

  ## Parameters
  - system_id: The solar system ID to fetch kills for
  - since_hours: Number of hours to look back from now
  - limit: Maximum number of kills to return

  ## Returns
  - {:ok, [kill()]} - List of killmail data
  - {:error, term()} - Error occurred during fetch
  """
  @callback fetch_system_kills(
              system_id :: integer(),
              since_hours :: integer(),
              limit :: integer()
            ) ::
              {:ok, [kill()]} | {:error, term()}

  @doc """
  Fetches killmails for multiple systems within the given time window.

  ## Parameters
  - system_ids: List of solar system IDs to fetch kills for
  - since_hours: Number of hours to look back from now
  - limit: Maximum number of kills to return per system

  ## Returns
  - {:ok, %{integer() => [kill()]}} - Map of system_id to killmail lists
  - {:error, term()} - Error occurred during fetch
  """
  @callback fetch_systems_kills(
              system_ids :: [integer()],
              since_hours :: integer(),
              limit :: integer()
            ) ::
              {:ok, %{integer() => [kill()]}} | {:error, term()}

  @doc """
  Retrieves cached killmails for a specific system.

  ## Parameters
  - system_id: The solar system ID to get cached kills for

  ## Returns
  - [kill()] - List of cached killmail data (empty list if none cached)
  """
  @callback fetch_cached_kills(system_id :: integer()) :: [kill()]

  @doc """
  Retrieves cached killmails for multiple systems.

  ## Parameters
  - system_ids: List of solar system IDs to get cached kills for

  ## Returns
  - %{integer() => [kill()]} - Map of system_id to cached killmail lists
  """
  @callback fetch_cached_kills_for_systems(system_ids :: [integer()]) :: %{integer() => [kill()]}

  @doc """
  Subscribes to kill updates for specified systems.

  ## Parameters
  - subscriber_id: Unique identifier for the subscriber
  - system_ids: List of system IDs to subscribe to
  - callback_url: Optional webhook URL for notifications (nil for PubSub only)

  ## Returns
  - {:ok, subscription_id} - Subscription created successfully
  - {:error, term()} - Error occurred during subscription
  """
  @callback subscribe_to_kills(
              subscriber_id :: String.t(),
              system_ids :: [integer()],
              callback_url :: String.t() | nil
            ) ::
              {:ok, subscription_id :: String.t()} | {:error, term()}

  @doc """
  Unsubscribes from all kill updates for a subscriber.

  ## Parameters
  - subscriber_id: Unique identifier for the subscriber to unsubscribe

  ## Returns
  - :ok - Successfully unsubscribed
  - {:error, term()} - Error occurred during unsubscription
  """
  @callback unsubscribe_from_kills(subscriber_id :: String.t()) :: :ok | {:error, term()}

  @doc """
  Retrieves a specific killmail by ID.

  ## Parameters
  - killmail_id: The killmail ID to retrieve

  ## Returns
  - kill() - The killmail data if found
  - nil - Killmail not found
  """
  @callback get_killmail(killmail_id :: integer()) :: kill() | nil

  @doc """
  Gets the current kill count for a system.

  ## Parameters
  - system_id: The solar system ID to get kill count for

  ## Returns
  - integer() - Current kill count for the system
  """
  @callback get_system_kill_count(system_id :: integer()) :: integer()
end
