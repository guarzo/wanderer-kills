defmodule WandererKills.Parser do
  @moduledoc """
  Backward compatibility alias for Parser.

  This module has been reorganized into the WandererKills.Parser.* namespace
  to better organize the codebase structure.

  The main parsing functionality is now in WandererKills.Parser.Coordinator.
  """

  alias WandererKills.Parser.Coordinator

  @type killmail :: map()
  @type raw_killmail :: map()

  # Delegate all functions to the coordinator
  defdelegate parse_full_and_store(full, partial, cutoff), to: Coordinator
  defdelegate parse_partial(partial, cutoff), to: Coordinator
end
