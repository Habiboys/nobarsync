defmodule NobarSyncWeb.Presence do
  use Phoenix.Presence,
    otp_app: :nobarsync,
    pubsub_server: NobarSync.PubSub
end
