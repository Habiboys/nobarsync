defmodule NobarSync.Playback.Broadcaster do
  @moduledoc false

  def broadcast(topic, event, payload) do
    Phoenix.PubSub.broadcast(NobarSync.PubSub, topic, %Phoenix.Socket.Broadcast{
      topic: topic,
      event: event,
      payload: payload
    })
  end
end
