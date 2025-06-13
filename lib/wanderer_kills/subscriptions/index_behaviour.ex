defmodule WandererKills.Subscriptions.IndexBehaviour do
  @moduledoc """
  Behaviour definition for subscription index implementations.

  Defines the common interface that all subscription indexes must implement,
  whether for characters, systems, or future entity types.

  ## Usage

  Modules implementing this behaviour provide O(1) lookup capabilities for
  finding subscriptions interested in specific entities. The implementation
  maintains dual data structures:

  - **Forward Index (ETS)**: `entity_id => MapSet[subscription_ids]`
  - **Reverse Index (Map)**: `subscription_id => [entity_ids]`

  ## Example

      defmodule MyIndex do
        @behaviour WandererKills.Subscriptions.IndexBehaviour
        
        # Implementation...
      end
  """

  @type entity_id :: integer()
  @type subscription_id :: String.t()
  @type index_stats :: %{
          total_subscriptions: non_neg_integer(),
          total_entity_entries: non_neg_integer(),
          total_entity_subscriptions: non_neg_integer(),
          memory_usage_bytes: non_neg_integer()
        }

  @doc """
  Starts the index GenServer.

  ## Parameters
    - `opts` - Keyword list of options
    
  ## Returns
    - `{:ok, pid}` on success
    - `{:error, reason}` on failure
  """
  @callback start_link(keyword()) :: GenServer.on_start()

  @doc """
  Adds a subscription to the index.

  ## Parameters
    - `subscription_id` - The unique subscription identifier
    - `entity_ids` - List of entity IDs this subscription is interested in
    
  ## Returns
    - `:ok` on success
  """
  @callback add_subscription(subscription_id(), [entity_id()]) :: :ok

  @doc """
  Updates a subscription's entity list in the index.

  Efficiently handles additions and removals by calculating the diff
  between old and new entity lists.

  ## Parameters
    - `subscription_id` - The subscription identifier to update
    - `entity_ids` - New list of entity IDs for this subscription
    
  ## Returns
    - `:ok` on success
  """
  @callback update_subscription(subscription_id(), [entity_id()]) :: :ok

  @doc """
  Removes a subscription from the index.

  Cleans up all forward index entries for this subscription and
  removes it from the reverse index.

  ## Parameters
    - `subscription_id` - The subscription identifier to remove
    
  ## Returns
    - `:ok` on success
  """
  @callback remove_subscription(subscription_id()) :: :ok

  @doc """
  Finds all subscription IDs interested in a specific entity.

  Provides O(1) lookup performance using the ETS forward index.

  ## Parameters
    - `entity_id` - The entity ID to look up
    
  ## Returns
    - List of subscription IDs interested in this entity
  """
  @callback find_subscriptions_for_entity(entity_id()) :: [subscription_id()]

  @doc """
  Finds all subscription IDs interested in any of the given entities.

  Returns a deduplicated list of subscription IDs that are interested
  in at least one of the provided entities.

  ## Parameters
    - `entity_ids` - List of entity IDs to look up
    
  ## Returns
    - Deduplicated list of subscription IDs
  """
  @callback find_subscriptions_for_entities([entity_id()]) :: [subscription_id()]

  @doc """
  Gets statistics about the index.

  Returns comprehensive metrics about index usage, performance,
  and memory consumption.

  ## Returns
    - Map containing index statistics
  """
  @callback get_stats() :: index_stats()

  @doc """
  Clears all data from the index.

  Useful for testing and maintenance operations.

  ## Returns
    - `:ok` on success
  """
  @callback clear() :: :ok
end
