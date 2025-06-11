defmodule WandererKillsWeb.ErrorView do
  @moduledoc """
  Error view for API responses.

  Since this is an API-only application, all errors are returned as JSON.
  """

  # For API-only app, always return JSON with status code
  def render(template, _assigns) do
    status_code = template |> String.split(".") |> hd() |> String.to_integer()
    status_message = Phoenix.Controller.status_message_from_template(template)

    %{
      error: status_message,
      status: status_code
    }
  end
end
