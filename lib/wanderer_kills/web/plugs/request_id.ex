defmodule WandererKills.Web.Plugs.RequestId do
  @moduledoc """
  Plug for handling request IDs.
  Generates a unique request ID for each request and stores it in the process dictionary.
  Also attaches the request ID to logger metadata for consistent logging.
  """

  import Plug.Conn
  require Logger

  @doc """
  Initializes the plug.
  """
  def init(opts), do: opts

  @doc """
  Generates a request ID, stores it in the process dictionary,
  attaches it to logger metadata, and adds it to the response headers.
  """
  def call(conn, _opts) do
    request_id = UUID.uuid4()
    Process.put(:request_id, request_id)
    Logger.metadata(request_id: request_id)
    put_resp_header(conn, "x-request-id", request_id)
  end
end
