defmodule WandererKillsWeb.Plugs.RequestId do
  @moduledoc """
  Plug to add request ID to all HTTP requests.

  Generates a unique request ID for each request and adds it to:
  - Logger metadata
  - Process dictionary
  - Response headers
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    request_id = UUID.uuid4()

    # Add to process metadata for logging
    Process.put(:request_id, request_id)
    Logger.metadata(request_id: request_id)

    # Add to response headers
    put_resp_header(conn, "x-request-id", request_id)
  end
end
