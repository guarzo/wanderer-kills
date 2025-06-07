defmodule WandererKills.Enricher do
  @moduledoc """
  DEPRECATED: This module has been moved to WandererKills.Killmails.Enricher.

  Please update your imports to use the new module path.
  This module is kept temporarily for backward compatibility.
  """

  alias WandererKills.Killmails.Enricher

  @deprecated "Use WandererKills.Killmails.Enricher.enrich_killmail/1 instead"
  defdelegate enrich_killmail(killmail), to: Enricher
end
