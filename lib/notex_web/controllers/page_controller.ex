defmodule NotexWeb.PageController do
  use NotexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
