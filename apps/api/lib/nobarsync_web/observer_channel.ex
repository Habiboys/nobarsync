defmodule NobarSyncWeb.ObserverChannel do
  use NobarSyncWeb, :channel

  def join("observe:room:" <> code, _, socket) do
    case NobarSync.WatchRooms.get_room_by_code(code) do
      nil ->
        {:error, %{code: "not_found"}}

      room ->
        Phoenix.PubSub.subscribe(NobarSync.PubSub, "room:#{room.id}")
        {:ok, socket}
    end
  end

  def join("observe:admin", _, socket) do
    case NobarSync.Accounts.get_user(socket.assigns.user_id) do
      %{role: "admin", status: "active"} ->
        Phoenix.PubSub.subscribe(NobarSync.PubSub, "activity:online")
        Phoenix.PubSub.subscribe(NobarSync.PubSub, "monitor:changes")
        {:ok, socket}

      _ ->
        {:error, %{code: "forbidden"}}
    end
  end

  def join(_, _, _), do: {:error, %{code: "forbidden"}}

  def handle_info(%Phoenix.Socket.Broadcast{}, socket) do
    # Coalesce presence fan-out and playback bursts before refreshing the read-only view.
    if !socket.assigns[:notice_pending], do: Process.send_after(self(), :changed, 100)
    {:noreply, assign(socket, :notice_pending, true)}
  end

  def handle_info(:changed, socket) do
    push(socket, "activity.changed", %{})
    {:noreply, assign(socket, :notice_pending, false)}
  end
end
