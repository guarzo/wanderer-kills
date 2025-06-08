defmodule WandererKillsWeb.ErrorView do
  # Simple error view returning plain text

  def render("404.html", _assigns) do
    "Not Found"
  end

  def render("404.json", _assigns) do
    %{error: "Not Found"}
  end

  def render("500.html", _assigns) do
    "Internal Server Error"
  end

  def render("500.json", _assigns) do
    %{error: "Internal Server Error"}
  end

  def render(template, _assigns) do
    status = Phoenix.Controller.status_message_from_template(template)

    if String.ends_with?(template, ".json") do
      %{error: status}
    else
      status
    end
  end

  def template_not_found(template, _assigns) do
    status = Phoenix.Controller.status_message_from_template(template)

    if String.ends_with?(template, ".json") do
      %{error: status}
    else
      status
    end
  end
end
