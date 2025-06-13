defmodule WandererKillsWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import WandererKillsWeb.ChannelCase

      # The default endpoint for testing
      @endpoint WandererKillsWeb.Endpoint
    end
  end

  setup _tags do
    :ok
  end
end
