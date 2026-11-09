defmodule NobarSyncWeb.UserSocket do
  use Phoenix.Socket

  channel "voice:*", NobarSyncWeb.VoiceChannel
  channel "room:*", NobarSyncWeb.RoomChannel
  channel "user:*", NobarSyncWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _info) do
    case Phoenix.Token.verify(NobarSyncWeb.Endpoint, "socket", token, max_age: 120) do
      {:ok, %{user_id: user_id, guest_id: nil, auth_version: version}} when is_binary(user_id) ->
        case NobarSync.Accounts.get_user(user_id) do
          %{status: "active", auth_version: ^version} ->
            {:ok, assign(socket, user_id: user_id, guest_id: nil)}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  def connect(_, _, _), do: :error

  @impl true
  def id(socket), do: "socket:#{socket.assigns.user_id || socket.assigns.guest_id}"
end
