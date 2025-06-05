defmodule WandererKills.CircuitBreaker do
  @moduledoc """
  Backward compatibility alias for CircuitBreaker.

  This module has been moved to WandererKills.Core.CircuitBreaker
  to better organize the codebase structure.
  """

  alias WandererKills.Core.CircuitBreaker

  # Delegate all functions to the new location
  defdelegate execute(service, fun), to: CircuitBreaker
  defdelegate force_open(service), to: CircuitBreaker
  defdelegate force_close(service), to: CircuitBreaker

  # Backward compatibility aliases
  def call(service, fun), do: execute(service, fun)
  def call(service, fun, _opts), do: execute(service, fun)
  def reset(service), do: force_close(service)
  def force_closed(service), do: force_open(service)
  def get_state(_service), do: {:error, :not_implemented}
end
