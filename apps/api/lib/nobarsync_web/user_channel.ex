defmodule NobarSyncWeb.UserChannel do
  use NobarSyncWeb, :channel

  def join("user:" <> user_id, _payload, socket) do
    if socket.assigns.user_id == user_id do
      send(self(), :track_activity)
      {:ok, socket}
    else
      {:error, %{code: "forbidden", message: "Bukan channel pengguna ini"}}
    end
  end

  def handle_info(:track_activity, socket) do
    NobarSyncWeb.Presence.track(self(), "activity:online", socket.assigns.user_id, %{
      page: "/",
      online_at: System.os_time(:second)
    })

    {:noreply, socket}
  end

  def handle_in("activity.page", %{"page" => page}, socket) when is_binary(page) do
    # Store route names only, never query strings containing invitation or media keys.
    if Regex.match?(
         ~r"^/(?:|dashboard|library|profile|admin|join|rooms/(?:new|[A-Za-z0-9_-]{4,12})|watch/[A-Za-z0-9_-]{4,12}|j/[A-Za-z0-9_-]{4,12})$",
         page
       ) do
      NobarSyncWeb.Presence.update(
        self(),
        "activity:online",
        socket.assigns.user_id,
        &Map.put(&1, :page, page)
      )
    end

    {:reply, :ok, socket}
  end
end
