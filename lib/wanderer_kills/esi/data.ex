defmodule WandererKills.Esi.Data do
  @moduledoc """
  ESI data structures and utilities.

  This module serves as an entry point for all ESI-related data structures
  and provides convenient access to types and utilities.

  ## Quick Access

  ```elixir
  alias WandererKills.Esi.Data

  # Access types directly
  character = %Data.Types.CharacterInfo{...}

  # Or use the Types module directly
  alias WandererKills.Esi.Data.Types
  character = %Types.CharacterInfo{...}
  ```

  ## Available Modules

  - `Types` - All ESI response data structures

  ## ESI Schema Reference

  This module contains data structures that correspond to ESI API endpoints:

  - **Characters**: `/characters/{character_id}/`
  - **Corporations**: `/corporations/{corporation_id}/`
  - **Alliances**: `/alliances/{alliance_id}/`
  - **Universe Types**: `/universe/types/{type_id}/`
  - **Universe Groups**: `/universe/groups/{group_id}/`
  - **Universe Systems**: `/universe/systems/{system_id}/`

  For the most up-to-date ESI documentation, see: https://esi.evetech.net/ui/
  """

  # Re-export Types for convenience
  alias WandererKills.Esi.Data.Types

  @typedoc """
  Type union for all ESI data structures.
  """
  @type esi_data :: Types.t()
end
