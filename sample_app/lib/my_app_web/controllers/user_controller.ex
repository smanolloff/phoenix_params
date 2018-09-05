defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller

  plug MyAppWeb.Requests.User.Create when action == :create

  def create(conn, params) do
    IO.inspect(params)
    json(conn, %{result: "ok"})
  end
end
