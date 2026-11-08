defmodule NobarSync.WatchRooms.CloseEmptyRoomsWorker do
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    NobarSync.WatchRooms.close_expired_empty()
    :ok
  end
end
