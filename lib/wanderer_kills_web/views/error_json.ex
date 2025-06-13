defmodule WandererKillsWeb.ErrorJSON do
  @moduledoc """
  JSON error rendering for API responses.
  """

  # By default, Phoenix calls this for exceptions
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
