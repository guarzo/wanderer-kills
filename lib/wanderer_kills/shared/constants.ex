defmodule WandererKills.Constants do
  @moduledoc """
  DEPRECATED: This module has been moved to WandererKills.Infrastructure.Constants.

  Please update your imports to use the new module path.
  This module is kept temporarily for backward compatibility.
  """

  alias WandererKills.Infrastructure.Constants

  @deprecated "Use WandererKills.Infrastructure.Constants.http_status/1 instead"
  defdelegate http_status(type), to: Constants

  @deprecated "Use WandererKills.Infrastructure.Constants.timeout/1 instead"
  defdelegate timeout(type), to: Constants

  @deprecated "Use WandererKills.Infrastructure.Constants.retry_config/1 instead"
  defdelegate retry_config(type), to: Constants

  @deprecated "Use WandererKills.Infrastructure.Constants.concurrency/1 instead"
  defdelegate concurrency(type), to: Constants

  @deprecated "Use WandererKills.Infrastructure.Constants.threshold/1 instead"
  defdelegate threshold(type), to: Constants

  @deprecated "Use WandererKills.Infrastructure.Constants.validation/1 instead"
  defdelegate validation(type), to: Constants

  @deprecated "Use WandererKills.Infrastructure.Constants.circuit_breaker/1 instead"
  defdelegate circuit_breaker(type), to: Constants

  @deprecated "Use WandererKills.Infrastructure.Constants.telemetry/1 instead"
  defdelegate telemetry(type), to: Constants
end
