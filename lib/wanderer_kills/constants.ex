defmodule WandererKills.Constants do
  @moduledoc """
  Backward compatibility alias for Constants.

  This module has been moved to WandererKills.Core.Constants
  to better organize the codebase structure.
  """

  alias WandererKills.Core.Constants

  # Delegate all functions to the new location
  defdelegate cache_ttl(type), to: Constants
  defdelegate retry_config(type), to: Constants
  defdelegate timeout(type), to: Constants
  defdelegate concurrency(type), to: Constants
  defdelegate threshold(type), to: Constants
  defdelegate http_status(type), to: Constants
  defdelegate validation(type), to: Constants
  defdelegate circuit_breaker(type), to: Constants
  defdelegate telemetry(type), to: Constants
end
