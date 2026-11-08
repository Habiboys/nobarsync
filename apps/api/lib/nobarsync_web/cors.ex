defmodule NobarSyncWeb.CORS do
  import Plug.Conn

  def origin(conn) do
    case get_req_header(conn, "origin") do
      [origin] -> if allowed?(origin), do: origin, else: nil
      _ -> nil
    end
  end

  def allowed?(origin) do
    base = Application.get_env(:nobarsync, :web_origin, "http://localhost:5173")
    origin in [base, "http://localhost:5173", "http://localhost:8080", "http://127.0.0.1:5173"]
  end
end
