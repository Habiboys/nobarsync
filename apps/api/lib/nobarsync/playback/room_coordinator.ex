defmodule NobarSync.Playback.RoomCoordinator do
  @moduledoc false
  use GenServer

  alias NobarSync.Analytics.Metrics
  alias NobarSync.Playback.{Broadcaster, BufferingPolicy, CommandHandler, Lease, StatePersistence}

  @grace_ms 1_500
  @resume_timeout_ms 12_000
  @host_grace_ms 20_000

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  def child_spec(room_id) do
    %{
      id: {__MODULE__, room_id},
      start: {__MODULE__, :start_link, [room_id]},
      restart: :transient,
      shutdown: 10_000
    }
  end

  def via(room_id), do: {:via, Registry, {NobarSync.Playback.Registry, room_id}}

  def ensure_started(room_id) do
    case Registry.lookup(NobarSync.Playback.Registry, room_id) do
      [{pid, _}] ->
        allow(pid)
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(
               NobarSync.Playback.CoordinatorSupervisor,
               child_spec(room_id)
             ) do
          {:ok, pid} ->
            allow(pid)
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            allow(pid)
            {:ok, pid}

          other ->
            other
        end
    end
  end

  def stop(room_id) do
    case Registry.lookup(NobarSync.Playback.Registry, room_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(NobarSync.Playback.CoordinatorSupervisor, pid)

      [] ->
        :ok
    end
  end

  def snapshot(room_id), do: GenServer.call(via(room_id), :snapshot)
  def command(room_id, command), do: GenServer.call(via(room_id), {:command, command})
  def player_signal(room_id, signal), do: GenServer.cast(via(room_id), {:player, signal})
  def heartbeat(room_id, beat), do: GenServer.cast(via(room_id), {:heartbeat, beat})
  def settings(room_id, attrs), do: GenServer.cast(via(room_id), {:settings, attrs})
  def presence(room_id, members), do: GenServer.cast(via(room_id), {:presence, members})

  def persist_all do
    NobarSync.Playback.Registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [:"$2"]}])
    |> Enum.each(fn pid ->
      try do
        GenServer.call(pid, :persist, 5_000)
      catch
        :exit, _ -> :ok
      end
    end)
  end

  @impl true
  def init(room_id) do
    case Lease.acquire(room_id) do
      {:ok, token} ->
        state =
          room_id
          |> StatePersistence.restore()
          |> Map.put(:fencing_token, token)
          |> clamp_runaway_position()

        Process.send_after(self(), :renew_lease, 10_000)
        Process.send_after(self(), :persist_tick, 5_000)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    state = tick(state)
    {:reply, public(state), state}
  end

  def handle_call(:persist, _from, state) do
    state = tick(state)
    StatePersistence.save(state)
    {:reply, :ok, state}
  end

  def handle_call({:command, command}, _from, state) do
    state = tick(state)
    request_id = command[:request_id]

    cond do
      is_binary(request_id) and Map.has_key?(state.request_ids, request_id) ->
        {:reply, {:ok, state.request_ids[request_id]}, state}

      command.type not in [:play, :pause, :seek, :change_media, :countdown] ->
        {:reply, {:error, :invalid}, state}

      not CommandHandler.authorize?(state.control_mode, command.role, command.type) ->
        {:reply, {:error, :forbidden}, state}

      is_nil(state.media_id) and command.type != :change_media ->
        {:reply, {:error, :media_not_ready}, state}

      command.type == :change_media and command[:provider] != "youtube" and
          command[:media_status] != "ready" ->
        {:reply, {:error, :media_not_ready}, state}

      command.type in [:play, :countdown] and
          Enum.any?(state.members, fn {_id, m} -> m[:role] == :host and m[:buffering] == true end) ->
        {:reply, {:error, :host_buffering}, state}

      command.type == :countdown and not is_nil(state.pending_transition) and
          state.pending_transition.status == :playing ->
        {:reply, {:ok, public(state)}, state}

      true ->
        {payload, state} = schedule(state, normalize(command))
        {:reply, {:ok, payload}, state}
    end
  end

  @impl true
  def handle_cast({:heartbeat, beat}, state) do
    if is_number(beat[:drift_ms]), do: Metrics.record_drift(state.room_id, beat[:drift_ms])
    if beat[:buffering], do: Metrics.record_buffer(state.room_id)

    next =
      state
      |> learn_duration(beat[:duration_ms])
      |> record_member_beat(beat)
      |> consider_buffer()

    if next.duration_ms != state.duration_ms or
         next.anchor_position_ms != state.anchor_position_ms do
      broadcast(next)
    end

    if beat[:role] == :host, do: broadcast_telemetry(next)
    {:noreply, next}
  end

  def handle_cast({:player, signal}, state) do
    member_id = signal.member_id

    members =
      Map.update(state.members, member_id, signal, fn prev ->
        Map.merge(prev, signal)
      end)

    next = consider_buffer(%{tick(state) | members: members})

    next =
      cond do
        signal.role == :host and signal.buffering and next.status == :playing and
            is_nil(next.pending_transition) ->
          {_payload, paused} =
            schedule(next, %{
              type: :pause,
              role: :host,
              member_id: member_id,
              request_id: unique(),
              position_ms: signal[:position_ms],
              rtt_ms: 0,
              countdown: false,
              immediate: true
            })

          held = Map.put(tick(paused), :host_buffer_hold, true)
          StatePersistence.save(held)
          held

        signal.role == :host and signal.ready and Map.get(next, :host_buffer_hold, false) ->
          {_payload, resumed} =
            schedule(tick(next), %{
              type: :play,
              role: :host,
              member_id: member_id,
              request_id: unique(),
              position_ms: signal[:position_ms],
              rtt_ms: 0,
              countdown: false
            })

          Map.put(resumed, :host_buffer_hold, false)

        true ->
          next
      end

    broadcast(next)
    broadcast_telemetry(next)
    {:noreply, next}
  end

  def handle_cast({:settings, attrs}, state) do
    next = %{state | control_mode: attrs.control_mode, buffering_mode: attrs.buffering_mode}
    broadcast(next)
    {:noreply, next}
  end

  def handle_cast({:presence, members}, state) do
    mapped =
      Map.new(members, fn member ->
        prev = Map.get(state.members, member.member_id, %{})

        {member.member_id,
         Map.merge(prev, %{
           member_id: member.member_id,
           display_name: member[:display_name] || Map.get(prev, :display_name, "Penonton"),
           online: member.online,
           role: member.role,
           buffering: Map.get(prev, :buffering, false),
           ready: Map.get(prev, :ready, false),
           position_ms: Map.get(prev, :position_ms, 0),
           paused: Map.get(prev, :paused, true),
           updated_at_ms: Map.get(prev, :updated_at_ms, 0)
         })}
      end)

    next = maybe_host_transfer(%{state | members: mapped})
    broadcast_telemetry(next)
    {:noreply, next}
  end

  @impl true
  def handle_info({:apply, revision}, state) do
    state =
      case state.pending_transition do
        %{revision: ^revision} = pending ->
          now_mono = System.monotonic_time(:millisecond)
          now_wall = System.os_time(:millisecond)
          state = CommandHandler.activate(%{state | timer_ref: nil}, pending, now_mono, now_wall)
          StatePersistence.save(state)
          broadcast(state)
          state

        _ ->
          state
      end

    {:noreply, state}
  end

  def handle_info(:renew_lease, state) do
    Lease.renew(state.room_id, state.fencing_token)
    Process.send_after(self(), :renew_lease, 10_000)
    {:noreply, state}
  end

  def handle_info(:persist_tick, state) do
    state = tick(state)
    if state.status == :playing, do: StatePersistence.save(state)
    Process.send_after(self(), :persist_tick, 5_000)
    {:noreply, state}
  end

  def handle_info(:buffer_grace, state), do: {:noreply, maybe_pause_for_buffer(state)}

  def handle_info(:buffer_timeout, state) do
    state =
      if state.paused_by_buffer and state.status == :paused do
        {_payload, state} =
          schedule(state, %{
            type: :play,
            role: :host,
            request_id: unique(),
            member_id: nil,
            rtt_ms: 0,
            countdown: false
          })

        %{state | paused_by_buffer: false}
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(:host_grace, state), do: {:noreply, transfer_if_host_gone(state)}

  @impl true
  def terminate(_reason, state) do
    StatePersistence.save(state)
    Lease.release(state.room_id, state.fencing_token)
    :ok
  end

  defp schedule(state, command) do
    cancel_timer(state)
    now_mono = System.monotonic_time(:millisecond)
    now_wall = System.os_time(:millisecond)
    state = CommandHandler.drop_future_pending(state, now_mono, now_wall)

    lead =
      cond do
        command[:immediate] -> 0
        command[:countdown] -> 3_000
        true -> CommandHandler.lead_ms(command[:rtt_ms])
      end

    {:ok, state, _pending} = CommandHandler.schedule(state, command, now_mono, now_wall, lead)
    ref = Process.send_after(self(), {:apply, state.revision}, lead)

    state =
      %{state | timer_ref: ref, paused_by_buffer: false} |> Map.put(:host_buffer_hold, false)

    StatePersistence.save(state)
    _ = StatePersistence.save_event(state, command)
    payload = public(state)
    broadcast(state, payload)

    if command.type == :change_media do
      Broadcaster.broadcast("room:#{state.room_id}", "room.media_changed", payload)
    end

    {payload, remember(state, command[:request_id], payload)}
  end

  defp tick(state) do
    now_mono = System.monotonic_time(:millisecond)
    now_wall = System.os_time(:millisecond)
    CommandHandler.activate_due(state, now_mono, now_wall)
  end

  defp consider_buffer(state) do
    decision =
      BufferingPolicy.decide(state.buffering_mode, Map.values(state.members),
        paused_by_buffer: state.paused_by_buffer
      )

    case decision do
      :pause when state.status == :playing and is_nil(state.buffer_since) ->
        Process.send_after(self(), :buffer_grace, @grace_ms)
        %{state | buffer_since: System.monotonic_time(:millisecond)}

      :resume when state.status == :paused ->
        {_payload, next} =
          schedule(state, %{
            type: :play,
            role: :host,
            request_id: unique(),
            member_id: nil,
            rtt_ms: 0,
            countdown: false
          })

        %{next | paused_by_buffer: false, buffer_since: nil}

      :none ->
        %{state | buffer_since: nil}

      _ ->
        state
    end
  end

  defp maybe_pause_for_buffer(state) do
    decision =
      BufferingPolicy.decide(state.buffering_mode, Map.values(state.members),
        paused_by_buffer: state.paused_by_buffer
      )

    if decision == :pause and state.status == :playing do
      {_payload, state} =
        schedule(%{state | buffer_since: nil}, %{
          type: :pause,
          role: :host,
          request_id: unique(),
          member_id: nil,
          rtt_ms: 0,
          countdown: false
        })

      Process.send_after(self(), :buffer_timeout, @resume_timeout_ms)

      Broadcaster.broadcast("room:#{state.room_id}", "room.error", %{
        v: 1,
        code: "buffer_pause",
        message: "Pemutaran dijeda karena beberapa penonton sedang buffering."
      })

      %{state | paused_by_buffer: true}
    else
      %{state | buffer_since: nil}
    end
  end

  defp maybe_host_transfer(state) do
    host_online? =
      Enum.any?(state.members, fn {_id, member} -> member.role == :host and member.online end)

    cond do
      host_online? ->
        %{state | host_absent_since: nil}

      is_nil(state.host_absent_since) ->
        Process.send_after(self(), :host_grace, host_grace())
        %{state | host_absent_since: System.monotonic_time(:millisecond)}

      true ->
        state
    end
  end

  defp transfer_if_host_gone(state) do
    host_online? =
      Enum.any?(state.members, fn {_id, member} -> member.role == :host and member.online end)

    if host_online? or is_nil(state.host_absent_since) do
      state
    else
      case NobarSync.WatchRooms.transfer_host_auto(state.room_id) do
        {:ok, room, member} ->
          Broadcaster.broadcast("room:#{state.room_id}", "room.host_changed", %{
            v: 1,
            room_id: state.room_id,
            host_user_id: room.host_user_id,
            member_id: member.id,
            display_name: member.display_name
          })

          %{state | host_absent_since: nil}

        _ ->
          %{state | host_absent_since: nil}
      end
    end
  end

  defp learn_duration(state, duration)
       when is_integer(duration) and duration > 1_000 and duration < 86_400_000 do
    known = if (state.duration_ms || 0) > 0, do: state.duration_ms, else: duration
    anchor = place_anchor(state.anchor_position_ms, known)

    if state.duration_ms == known and state.anchor_position_ms == anchor do
      state
    else
      %{state | duration_ms: known, anchor_position_ms: anchor}
    end
  end

  defp learn_duration(state, _), do: state

  defp clamp_runaway_position(state) do
    case known_duration(state) do
      duration when duration > 0 ->
        anchor = place_anchor(state.anchor_position_ms, duration)
        finished = state.status == :playing and anchor >= duration - 500
        anchor = if finished, do: 0, else: anchor

        same =
          state.duration_ms == duration and state.anchor_position_ms == anchor and not finished

        if same do
          state
        else
          %{
            state
            | duration_ms: duration,
              anchor_position_ms: anchor,
              anchor_wall_ms:
                if(finished, do: System.os_time(:millisecond), else: state.anchor_wall_ms),
              anchor_mono_ms:
                if(finished, do: System.monotonic_time(:millisecond), else: state.anchor_mono_ms)
          }
        end

      _ ->
        state
    end
  end

  defp known_duration(%{duration_ms: duration}) when is_integer(duration) and duration > 0,
    do: duration

  defp known_duration(%{media_id: id}) when is_binary(id) do
    case NobarSync.Media.get_asset(id) do
      %{duration_ms: duration} when is_integer(duration) and duration > 0 -> duration
      _ -> 0
    end
  end

  defp known_duration(_), do: 0

  defp place_anchor(anchor, duration) do
    anchor = anchor || 0

    cond do
      anchor > duration + 2_000 -> 0
      anchor > duration -> duration
      true -> anchor
    end
  end

  defp normalize(%{type: :countdown} = command),
    do: Map.merge(command, %{type: :play, countdown: true})

  defp normalize(command), do: Map.put_new(command, :countdown, false)

  defp public(state) do
    pending = state.pending_transition

    %{
      v: 1,
      room_id: state.room_id,
      revision: state.revision,
      media_id: state.media_id,
      duration_ms: state.duration_ms,
      control_mode: state.control_mode,
      buffering_mode: state.buffering_mode,
      server_wall_ms: System.os_time(:millisecond),
      effective_at_ms:
        if(pending, do: pending.effective_at_ms, else: System.os_time(:millisecond)),
      state: %{
        status: state.status,
        anchor_position_ms: state.anchor_position_ms,
        anchor_server_time_ms: state.anchor_wall_ms,
        playback_rate: state.playback_rate
      },
      pending:
        if(pending,
          do: %{
            status: pending.status,
            countdown: Map.get(pending, :countdown, false),
            kind: pending.kind,
            anchor_position_ms: pending.anchor_position_ms,
            anchor_server_time_ms: pending.anchor_wall_ms,
            playback_rate: pending.playback_rate,
            media_id: pending.media_id,
            duration_ms: pending.duration_ms
          },
          else: nil
        )
    }
  end

  defp broadcast(state, payload \\ nil) do
    Broadcaster.broadcast("room:#{state.room_id}", "playback.state", payload || public(state))
  end

  defp record_member_beat(state, %{member_id: id} = beat) when is_binary(id) do
    now_wall = System.os_time(:millisecond)

    entry = %{
      member_id: id,
      display_name: beat[:display_name] || "Penonton",
      role: beat[:role] || :viewer,
      online: true,
      position_ms:
        if(is_number(beat[:position_ms]), do: max(0, trunc(beat[:position_ms])), else: 0),
      paused: beat[:paused] == true,
      buffering: beat[:buffering] == true,
      ready: not (beat[:buffering] == true),
      updated_at_ms: now_wall
    }

    members =
      Map.update(state.members, id, entry, fn prev ->
        Map.merge(prev, entry)
      end)

    %{state | members: members}
  end

  defp record_member_beat(state, _), do: state

  defp broadcast_telemetry(state) do
    now_mono = System.monotonic_time(:millisecond)
    canonical = NobarSync.Playback.Timeline.position(state, now_mono)

    host_entry =
      state.members
      |> Map.values()
      |> Enum.find(fn m -> m[:role] == :host and m[:online] != false end)

    now_wall = System.os_time(:millisecond)
    host_pos = if host_entry, do: sample_position(host_entry, now_wall), else: canonical

    host_paused = if host_entry, do: host_entry[:paused] == true, else: state.status != :playing
    host_buffering = if host_entry, do: host_entry[:buffering] == true, else: false

    items =
      state.members
      |> Map.values()
      |> Enum.filter(&(&1[:online] != false and is_binary(&1[:member_id])))
      |> Enum.map(fn m ->
        pos = sample_position(m, now_wall)

        %{
          member_id: m[:member_id],
          display_name: m[:display_name] || "Penonton",
          role: to_string(m[:role] || :viewer),
          position_ms: pos,
          lag_ms: pos - host_pos,
          paused: m[:paused] == true,
          buffering: m[:buffering] == true,
          updated_at_ms: m[:updated_at_ms] || 0
        }
      end)

    Broadcaster.broadcast("room:#{state.room_id}", "room.telemetry", %{
      v: 1,
      host_position_ms: host_pos,
      host_paused: host_paused,
      host_buffering: host_buffering,
      members: items
    })
  end

  defp sample_position(member, now) do
    position = member[:position_ms] || 0
    elapsed = max(0, min(5_000, now - (member[:updated_at_ms] || now)))
    if member[:paused] or member[:buffering], do: position, else: position + elapsed
  end

  defp cancel_timer(%{timer_ref: ref}) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_timer(_), do: :ok

  defp remember(state, nil, _payload), do: state

  defp remember(state, request_id, payload) do
    ids =
      state.request_ids
      |> Map.put(request_id, payload)
      |> Enum.take(100)
      |> Map.new()

    %{state | request_ids: ids}
  end

  defp unique, do: Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

  defp host_grace do
    String.to_integer(System.get_env("HOST_TRANSFER_GRACE_MS") || "#{@host_grace_ms}")
  end

  defp allow(pid) do
    if Application.get_env(:nobarsync, :sql_sandbox) do
      Ecto.Adapters.SQL.Sandbox.allow(NobarSync.Repo, self(), pid)
    end

    :ok
  end
end
