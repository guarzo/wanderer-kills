defmodule WandererKills.ShipTypes.CSVParser do
  @moduledoc """
  DEPRECATED: This module has been replaced by WandererKills.ShipTypes.CSVHelpers.

  Please use CSVHelpers for all ship type CSV parsing functionality.
  This module is kept temporarily for backward compatibility.
  """

  alias WandererKills.ShipTypes.CSVHelpers

  @deprecated "Use WandererKills.ShipTypes.CSVHelpers.load_ship_data/0 instead"
  defdelegate load_ship_data(), to: CSVHelpers

  @deprecated "Use WandererKills.ShipTypes.CSVHelpers.load_ship_data/1 instead"
  defdelegate load_ship_data(data_dir), to: CSVHelpers
end
