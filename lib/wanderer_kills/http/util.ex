defmodule WandererKills.Http.Util do
  @moduledoc """
  **DEPRECATED**: This module has been consolidated into `WandererKills.Http.Client`.

  All functionality from this module has been moved to `WandererKills.Http.Client`
  and `WandererKills.Http.ClientProvider` for better organization and reduced duplication.

  ## Migration Guide

  Replace calls to:
  - `Http.Util.request_with_telemetry/3` → `Http.Client.request_with_telemetry/3`
  - `Http.Util.parse_json_response/1` → `Http.Client.parse_json_response/1`
  - `Http.Util.build_query_params/1` → `Http.ClientProvider.build_request_opts/1`
  - `Http.Util.eve_api_headers/1` → `Http.ClientProvider.eve_api_headers/0`
  - `Http.Util.retry_operation/3` → `Http.Client.retry_operation/3`
  - `Http.Util.validate_response_structure/2` → `Http.Client.validate_response_structure/2`
  """

  alias WandererKills.Http.{Client, ClientProvider}

  @deprecated "Use WandererKills.Http.Client.request_with_telemetry/3 instead"
  defdelegate request_with_telemetry(url, service, opts \\ []), to: Client

  @deprecated "Use WandererKills.Http.Client.parse_json_response/1 instead"
  defdelegate parse_json_response(response), to: Client

  @deprecated "Use WandererKills.Http.ClientProvider.build_request_opts/1 instead"
  def build_query_params(params) do
    # For backward compatibility, just return the params processed the same way
    ClientProvider.build_request_opts(params: params)[:params]
  end

  @deprecated "Use WandererKills.Http.ClientProvider.eve_api_headers/0 instead"
  def eve_api_headers(_user_agent \\ nil) do
    ClientProvider.eve_api_headers()
  end

  @deprecated "Use WandererKills.Http.Client.retry_operation/3 instead"
  defdelegate retry_operation(fun, service, opts \\ []), to: Client

  @deprecated "Use WandererKills.Http.Client.validate_response_structure/2 instead"
  defdelegate validate_response_structure(data, required_fields), to: Client
end
