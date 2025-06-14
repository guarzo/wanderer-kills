defmodule WandererKills.Subs.Subscriptions.Filter do
  @moduledoc """
  Provides filtering logic for matching killmails against subscriptions.

  This module encapsulates the logic for determining whether a killmail
  should be sent to a particular subscription based on system and/or
  character filtering criteria.

  ## Filtering Logic

  A killmail matches a subscription if **either** of the following is true:
  - The killmail's `solar_system_id` is in the subscription's `system_ids` list
  - The killmail contains a character (victim or attacker) in the subscription's `character_ids` list

  Empty filter lists are treated as "no filter" for that criterion.

  ## Performance Features

  - Automatic performance monitoring with telemetry
  - Warning logs for large filtering operations (>100 killmails + >50 characters)
  - Slow operation detection (>100ms) with detailed logging
  - Uses efficient character matching via `CharacterMatcher`

  ## Telemetry Events

  Emits `[:wanderer_kills, :character, :filter]` events with:
  - `duration` - Filtering duration in native time units
  - `killmail_count` - Number of killmails processed
  - `match_count` - Number of killmails that matched

  ## Examples

      # System-based filtering
      subscription = %{"system_ids" => [30000142], "character_ids" => []}
      killmail = %{"solar_system_id" => 30000142, "victim" => %{"character_id" => 123}}
      Filter.matches_subscription?(killmail, subscription) # => true

      # Character-based filtering  
      subscription = %{"system_ids" => [], "character_ids" => [123]}
      killmail = %{"solar_system_id" => 30000999, "victim" => %{"character_id" => 123}}
      Filter.matches_subscription?(killmail, subscription) # => true

      # Mixed filtering (OR logic)
      subscription = %{"system_ids" => [30000142], "character_ids" => [456]}
      killmail = %{"solar_system_id" => 30000999, "victim" => %{"character_id" => 456}}
      Filter.matches_subscription?(killmail, subscription) # => true (character match)
  """

  alias WandererKills.Ingest.Killmails.CharacterMatcher
  alias WandererKills.Core.Observability.Telemetry

  require Logger

  @doc """
  Checks if a killmail matches a subscription's filter criteria.

  A killmail matches if either:
  - The killmail's system_id matches one of the subscription's system_ids
  - The killmail contains a character (victim or attacker) matching one of the subscription's character_ids

  Empty lists are treated as "no filter" for that criterion.

  ## Parameters
    - `killmail` - The killmail map to check
    - `subscription` - The subscription map containing filter criteria

  ## Returns
    - `true` if the killmail matches the subscription
    - `false` otherwise

  ## Examples
      iex> subscription = %{"system_ids" => [30000142], "character_ids" => []}
      iex> killmail = %{"solar_system_id" => 30000142, "victim" => %{"character_id" => 123}}
      iex> Filter.matches_subscription?(killmail, subscription)
      true
  """
  @spec matches_subscription?(map(), map()) :: boolean()
  def matches_subscription?(killmail, subscription) do
    system_ids = subscription["system_ids"] || []
    character_ids = subscription["character_ids"] || []

    # If both lists are empty, this is a wildcard subscription (match everything)
    if Enum.empty?(system_ids) and Enum.empty?(character_ids) do
      true
    else
      system_match = check_system_match(killmail, subscription)
      character_match = check_character_match(killmail, subscription)

      system_match or character_match
    end
  end

  @doc """
  Filters a list of killmails to only those matching a subscription.

  This is useful when processing batches of killmails where some may not
  match the subscription's criteria.

  ## Parameters
    - `killmails` - List of killmail maps
    - `subscription` - The subscription map containing filter criteria

  ## Returns
    - List of killmails that match the subscription
  """
  @spec filter_killmails(list(map()), map()) :: list(map())
  def filter_killmails(killmails, subscription) do
    start_time = System.monotonic_time()
    killmail_count = length(killmails)
    character_count = length(subscription["character_ids"] || [])
    system_count = length(subscription["system_ids"] || [])

    # Log performance warning for large filtering operations
    if killmail_count > 100 and (character_count > 50 or system_count > 50) do
      Logger.warning("⚠️ Large filtering operation detected",
        killmail_count: killmail_count,
        character_count: character_count,
        system_count: system_count,
        operation: "batch_filter"
      )
    end

    result = Enum.filter(killmails, &matches_subscription?(&1, subscription))

    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    # Log slow filtering operations
    if duration_ms > 100 do
      Logger.info("🐌 Slow filtering detected",
        duration_ms: duration_ms,
        killmail_count: killmail_count,
        character_count: character_count,
        system_count: system_count,
        match_count: length(result)
      )
    end

    # Emit telemetry for both systems and characters if they're being used
    if character_count > 0 do
      Telemetry.character_filter(duration, killmail_count, length(result))
    end

    if system_count > 0 do
      Telemetry.system_filter(duration, killmail_count, length(result))
    end

    result
  end

  @doc """
  Checks if a subscription has any active filters.

  ## Parameters
    - `subscription` - The subscription map

  ## Returns
    - `true` if the subscription has system_ids or character_ids
    - `false` if both are empty/nil
  """
  @spec has_filters?(map()) :: boolean()
  def has_filters?(subscription) do
    has_system_filter?(subscription) or has_character_filter?(subscription)
  end

  @doc """
  Checks if a subscription has system filtering enabled.
  """
  @spec has_system_filter?(map()) :: boolean()
  def has_system_filter?(subscription) do
    case subscription["system_ids"] do
      nil -> false
      [] -> false
      _ -> true
    end
  end

  @doc """
  Checks if a subscription has character filtering enabled.
  """
  @spec has_character_filter?(map()) :: boolean()
  def has_character_filter?(subscription) do
    case subscription["character_ids"] do
      nil -> false
      [] -> false
      _ -> true
    end
  end

  # Private functions

  defp check_system_match(killmail, subscription) do
    case subscription["system_ids"] do
      nil ->
        false

      [] ->
        false

      system_ids ->
        system_id = killmail["solar_system_id"] || killmail["system_id"]
        system_id in system_ids
    end
  end

  defp check_character_match(killmail, subscription) do
    case subscription["character_ids"] do
      nil ->
        false

      [] ->
        false

      character_ids ->
        CharacterMatcher.killmail_has_characters?(killmail, character_ids)
    end
  end
end
