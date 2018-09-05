defmodule MyAppWeb.ErrorView do
  use MyAppWeb, :view

  def template_not_found(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end

  def render("400.json", %{conn: %Plug.Conn{assigns: %{validation_failed: errors}}}) do
    errors
  end
end
