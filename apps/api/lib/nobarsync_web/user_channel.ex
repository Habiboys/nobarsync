defmodule NobarSyncWeb.UserChannel do
  use NobarSyncWeb, :channel

  def join("user:" <> user_id, _payload, socket) do
    if socket.assigns.user_id == user_id do
      {:ok, socket}
    else
      {:error, %{code: "forbidden", message: "Bukan channel pengguna ini"}}
    end
  end
end
