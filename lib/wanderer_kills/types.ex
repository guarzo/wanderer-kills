defmodule WandererKills.Types do
  @moduledoc """
  Type definitions for WandererKills service data structures.

  This module defines the standard data structures used throughout the WandererKills service,
  ensuring consistency between API responses, cache storage, and client interfaces.
  """

  @typedoc """
  A complete killmail record with victim, attackers, and metadata.

  This represents the canonical killmail format used throughout the service.
  """
  @type killmail :: %{
          killmail_id: integer(),
          kill_time: DateTime.t(),
          system_id: integer(),
          victim: victim(),
          attackers: [attacker()],
          zkb: zkb_metadata()
        }

  @typedoc """
  Victim information in a killmail.
  """
  @type victim :: %{
          character_id: integer() | nil,
          corporation_id: integer(),
          alliance_id: integer() | nil,
          ship_type_id: integer(),
          damage_taken: integer()
        }

  @typedoc """
  Attacker information in a killmail.
  """
  @type attacker :: %{
          character_id: integer() | nil,
          corporation_id: integer() | nil,
          alliance_id: integer() | nil,
          ship_type_id: integer() | nil,
          weapon_type_id: integer() | nil,
          damage_done: integer(),
          final_blow: boolean()
        }

  @typedoc """
  zKillboard-specific metadata for a killmail.
  """
  @type zkb_metadata :: %{
          location_id: integer() | nil,
          hash: String.t(),
          fitted_value: float(),
          total_value: float(),
          points: integer(),
          npc: boolean(),
          solo: boolean(),
          awox: boolean()
        }

  @typedoc """
  Standard error response structure.
  """
  @type error_response :: %{
          error: String.t(),
          code: String.t(),
          details: map() | nil,
          timestamp: DateTime.t()
        }

  @typedoc """
  Standard success response wrapper.
  """
  @type success_response(data_type) :: %{
          data: data_type,
          timestamp: DateTime.t()
        }

  @typedoc """
  Subscription information.
  """
  @type subscription :: %{
          subscriber_id: String.t(),
          system_ids: [integer()],
          callback_url: String.t() | nil,
          created_at: DateTime.t()
        }

  @typedoc """
  Killmail count information for a system.
  """
  @type killmail_count :: %{
          system_id: integer(),
          count: integer(),
          timestamp: DateTime.t()
        }

  @typedoc """
  Multi-system killmail data response.
  """
  @type systems_killmails :: %{
          systems_killmails: %{integer() => [killmail()]},
          timestamp: DateTime.t()
        }

  @doc """
  Creates a standard success response envelope.
  """
  @spec success_response(any()) :: success_response(any())
  def success_response(data) do
    %{
      data: data,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a standard error response envelope.
  """
  @spec error_response(String.t(), String.t(), map() | nil) :: error_response()
  def error_response(message, code, details \\ nil) do
    %{
      error: message,
      code: code,
      details: details,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a killmail count response.
  """
  @spec killmail_count_response(integer(), integer()) :: killmail_count()
  def killmail_count_response(system_id, count) do
    %{
      system_id: system_id,
      count: count,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a systems killmails response.
  """
  @spec systems_killmails_response(%{integer() => [killmail()]}) :: systems_killmails()
  def systems_killmails_response(systems_killmails) do
    %{
      systems_killmails: systems_killmails,
      timestamp: DateTime.utc_now()
    }
  end
end
