defmodule WandererKills.Schema.Killmail do
  @moduledoc """
  Schema definition for killmail data structures.
  """

  @derive {Jason.Encoder,
           only: [
             :killmail_id,
             :kill_time,
             :solar_system_id,
             :attacker_count,
             :total_value,
             :npc,
             :victim,
             :attackers,
             :zkb,
             :final_blow
           ]}

  @type t :: %__MODULE__{
          killmail_id: integer(),
          kill_time: DateTime.t(),
          solar_system_id: integer(),
          attacker_count: integer(),
          total_value: integer(),
          npc: boolean(),
          victim: map(),
          attackers: list(map()),
          zkb: map(),
          final_blow: map() | nil
        }

  defstruct [
    :killmail_id,
    :kill_time,
    :solar_system_id,
    :attacker_count,
    :total_value,
    :npc,
    :victim,
    :attackers,
    :zkb,
    :final_blow
  ]
end
