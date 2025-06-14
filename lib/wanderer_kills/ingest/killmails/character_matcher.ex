defmodule WandererKills.Ingest.Killmails.CharacterMatcher do
  @moduledoc """
  Utilities for matching characters in killmails against subscription filters.

  This module provides functions to check if a killmail contains specific
  character IDs either as victims or attackers, supporting the character-based
  subscription filtering feature.

  ## Performance Characteristics

  - Uses MapSet for O(1) character ID lookups
  - Short-circuits on victim match before checking attackers
  - Handles large attacker lists efficiently
  - Includes telemetry for performance monitoring

  ## Telemetry Events

  Emits `[:wanderer_kills, :character, :match]` events with:
  - `duration` - Matching duration in native time units
  - `match_found` - 1 if match found, 0 otherwise
  - `character_count` - Number of characters being matched against

  ## Usage in Subscriptions

  This module is primarily used by the `WandererKills.Subs.Subscriptions.Filter`
  module to determine if killmails should be delivered to character-based
  subscriptions.
  """

  alias WandererKills.Core.Observability.Telemetry
  alias WandererKills.Domain.Killmail

  @doc """
  Checks if a killmail contains any of the specified character IDs.

  Returns true if the killmail's victim or any attacker matches one of the
  provided character IDs.

  ## Parameters
    - `killmail` - The killmail data structure (map)
    - `character_ids` - List of character IDs to match against

  ## Returns
    - `true` if any character ID matches
    - `false` if no matches found

  ## Examples
      iex> killmail = %{"victim" => %{"character_id" => 123}, "attackers" => []}
      iex> CharacterMatcher.killmail_has_characters?(killmail, [123, 456])
      true
      
      iex> killmail = %{"victim" => %{"character_id" => 789}, "attackers" => [%{"character_id" => 123}]}
      iex> CharacterMatcher.killmail_has_characters?(killmail, [123])
      true
  """
  @spec killmail_has_characters?(Killmail.t(), list(integer())) :: boolean()
  def killmail_has_characters?(_killmail, []), do: false
  def killmail_has_characters?(_killmail, nil), do: false

  def killmail_has_characters?(%Killmail{} = killmail, character_ids) when is_list(character_ids) do
    # Use struct fields directly for better performance
    start_time = System.monotonic_time()
    character_set = MapSet.new(character_ids)

    victim_match = killmail.victim && killmail.victim.character_id in character_set

    result =
      if victim_match do
        true
      else
        Enum.any?(killmail.attackers, fn attacker ->
          attacker.character_id && attacker.character_id in character_set
        end)
      end

    duration = System.monotonic_time() - start_time
    Telemetry.character_match(duration, result, length(character_ids))

    result
  end

  @doc """
  Extracts all unique character IDs from a killmail.

  Returns a list of all character IDs found in the killmail, including
  the victim and all attackers. Filters out nil values and returns
  only unique IDs.

  ## Parameters
    - `killmail` - The killmail data structure (map)

  ## Returns
    - List of unique character IDs (integers)

  ## Examples
      iex> killmail = %{
      ...>   "victim" => %{"character_id" => 123},
      ...>   "attackers" => [
      ...>     %{"character_id" => 456},
      ...>     %{"character_id" => 789},
      ...>     %{"character_id" => 123}
      ...>   ]
      ...> }
      iex> CharacterMatcher.extract_character_ids(killmail)
      [123, 456, 789]
  """
  @spec extract_character_ids(Killmail.t()) :: list(integer())
  def extract_character_ids(%Killmail{} = killmail) do
    victim_id = killmail.victim && killmail.victim.character_id
    attacker_ids = Enum.map(killmail.attackers, & &1.character_id)
    
    [victim_id | attacker_ids]
    |> Enum.filter(& &1)
    |> Enum.uniq()
    |> Enum.sort()
  end

end
