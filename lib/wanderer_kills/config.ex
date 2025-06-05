defmodule WandererKills.Config do
  @moduledoc """
  Backward compatibility alias for Config.

  This module has been moved to WandererKills.Core.Config
  to better organize the codebase structure.
  """

  alias WandererKills.Core.Config

  # Delegate all functions to the new location
  defdelegate zkb_base_url(), to: Config
  defdelegate port(), to: Config
  defdelegate cache(type), to: Config
  defdelegate cache(type, key), to: Config
  defdelegate cache(), to: Config
  defdelegate recent_fetch_threshold(), to: Config
  defdelegate retry(), to: Config
  defdelegate retry_config(type), to: Config
  defdelegate timeout(type), to: Config
  defdelegate concurrency(), to: Config
  defdelegate concurrency(type), to: Config
  defdelegate threshold(type), to: Config
  defdelegate http_status(type), to: Config
  defdelegate validation(type), to: Config
  defdelegate circuit_breaker(service), to: Config
  defdelegate telemetry(), to: Config
  defdelegate killmail_store(), to: Config
  defdelegate esi(), to: Config
  defdelegate redisq(), to: Config
  defdelegate parser(), to: Config
  defdelegate enricher(), to: Config
  defdelegate clock(), to: Config
end
