defmodule WandererKillsWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, channels and so on.

  This can be used in your application as:

      use WandererKillsWeb, :controller
  """

  def controller do
    quote do
      use Phoenix.Controller, namespace: WandererKillsWeb

      import Plug.Conn
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
