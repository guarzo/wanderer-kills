defmodule WandererKillsWeb.ErrorView do
  @moduledoc """
  Error view for API responses.

  Since this is an API-only application, all errors are returned as JSON.
  """

  # By default, Phoenix templates are named after the controller and action.
  # For errors, the template is the status code as a string, e.g. "404.json" or "500.json"
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end

  # Allows customization of specific error codes
  def template_not_found(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
