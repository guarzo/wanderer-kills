defmodule WandererKills.Core.Http.Errors do
  @moduledoc """
  Defines error types used in HTTP operations.
  """

  defmodule ConnectionError do
    @moduledoc """
    Error raised when a connection fails.
    """
    defexception [:message]
  end

  defmodule TimeoutError do
    @moduledoc """
    Error raised when a request times out.
    """
    defexception [:message]
  end

  defmodule RateLimitError do
    @moduledoc """
    Error raised when rate limit is exceeded.
    """
    defexception [:message]
  end
end
