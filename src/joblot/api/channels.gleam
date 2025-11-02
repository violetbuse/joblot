import gleam/bit_array
import gleam/bool
import gleam/bytes_tree
import gleam/dict
import gleam/erlang/process
import gleam/float
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/set
import gleam/time/timestamp
import joblot/channel
import joblot/pubsub
import joblot/util
import mist

const channel_socket_heartbeat_interval = 15_000

const max_already_received_size = 5000

const post_vacuum_starting_size = 2000

const already_received_keep_for = 1800

const channel_vacuum_interval = 120_000

pub fn api_handler(
  req: request.Request(mist.Connection),
  pubsub: process.Subject(pubsub.Message),
) -> response.Response(mist.ResponseData) {
  case request.path_segments(req) {
    ["api", "channels", channel_name, "socket"] ->
      handle_websocket_incoming(req, channel_name, pubsub)
    ["api", "channels", channel_name, "publish"] ->
      handle_publish(req, channel_name, pubsub)
    _ -> util.not_found()
  }
}

const mb_128 = 134_217_728

fn handle_publish(
  req: request.Request(mist.Connection),
  channel_name: String,
  pubsub: process.Subject(pubsub.Message),
) -> response.Response(mist.ResponseData) {
  let assert Ok(req) = mist.read_body(req, mb_128)
  case bit_array.to_string(req.body) {
    Ok(text) -> {
      let body =
        pubsub.publish(pubsub, channel_name, text)
        |> channel.encode_pubsub_event
        |> json.to_string_tree
        |> bytes_tree.from_string_tree
        |> mist.Bytes

      response.new(200) |> response.set_body(body)
    }
    Error(_) -> {
      let body =
        json.object([#("error", json.string("Event was invalid utf-8 text"))])
        |> json.to_string_tree
        |> bytes_tree.from_string_tree
        |> mist.Bytes

      response.new(400) |> response.set_body(body)
    }
  }
}

fn handle_websocket_incoming(
  req: request.Request(mist.Connection),
  channel_name: String,
  pubsub: process.Subject(pubsub.Message),
) -> response.Response(mist.ResponseData) {
  let replay_from =
    request.get_query(req)
    |> result.map(dict.from_list)
    |> result.unwrap(dict.new())
    |> dict.get("replay_from")
    |> result.map(int.parse)
    |> result.flatten
    |> option.from_result

  mist.websocket(
    req,
    channel_websocket_handler,
    channel_websocket_initializer(_, req, pubsub, channel_name, replay_from),
    channel_websocket_on_close,
  )
}

type ChannelSocketState {
  State(
    pubsub: process.Subject(pubsub.Message),
    channel_name: String,
    latest_event: option.Option(Int),
    self: process.Subject(ChannelSocketMessage),
    receiver: process.Subject(channel.PubsubEvent),
    already_received: set.Set(channel.PubsubEvent),
  )
}

type ChannelSocketMessage {
  Heartbeat
  Vacuum
  IncomingEvent(channel.PubsubEvent)
}

fn channel_websocket_initializer(
  _conn: mist.WebsocketConnection,
  _req: request.Request(mist.Connection),
  pubsub: process.Subject(pubsub.Message),
  channel_name: String,
  replay_from: option.Option(Int),
) -> #(
  ChannelSocketState,
  option.Option(process.Selector(ChannelSocketMessage)),
) {
  let self = process.new_subject()
  let receiver = process.new_subject()

  pubsub.subscribe(
    pubsub,
    channel: channel_name,
    receive: receiver,
    replay: replay_from,
  )
  process.send_after(self, channel_socket_heartbeat_interval, Heartbeat)
  process.send_after(self, channel_vacuum_interval, Vacuum)

  let state =
    State(
      pubsub:,
      channel_name:,
      self:,
      receiver:,
      latest_event: replay_from,
      already_received: set.new(),
    )

  let selector =
    process.new_selector()
    |> process.select(self)
    |> process.select_map(receiver, IncomingEvent)

  #(state, option.Some(selector))
}

fn channel_websocket_handler(
  state: ChannelSocketState,
  message: mist.WebsocketMessage(ChannelSocketMessage),
  conn: mist.WebsocketConnection,
) -> mist.Next(ChannelSocketState, ChannelSocketMessage) {
  case message {
    mist.Text(str) -> handle_websocket_text(state, str, conn)
    mist.Binary(binary) -> handle_websocket_binary(state, binary, conn)
    mist.Closed -> mist.stop()
    mist.Shutdown -> mist.stop_abnormal("Closed unexpectedly")
    mist.Custom(message) ->
      handle_websocket_custom_message(state, message, conn)
  }
}

fn handle_websocket_text(
  state: ChannelSocketState,
  text: String,
  _conn: mist.WebsocketConnection,
) -> mist.Next(ChannelSocketState, ChannelSocketMessage) {
  let event = pubsub.publish(state.pubsub, state.channel_name, text)
  mist.continue(
    State(..state, already_received: set.insert(state.already_received, event)),
  )
}

fn handle_websocket_binary(
  state: ChannelSocketState,
  binary: BitArray,
  conn: mist.WebsocketConnection,
) -> mist.Next(ChannelSocketState, ChannelSocketMessage) {
  case bit_array.to_string(binary) {
    Ok(str) -> handle_websocket_text(state, str, conn)
    Error(_) -> mist.stop_abnormal("Error decoding binary message.")
  }
}

fn handle_websocket_custom_message(
  state: ChannelSocketState,
  message: ChannelSocketMessage,
  conn: mist.WebsocketConnection,
) -> mist.Next(ChannelSocketState, ChannelSocketMessage) {
  case message {
    Heartbeat -> channel_websocket_handle_heartbeat(state)
    Vacuum -> channel_websocket_handle_vacuum(state)
    IncomingEvent(event) ->
      channel_websocket_handle_incoming_event(state, event, conn)
  }
}

fn channel_websocket_handle_heartbeat(
  state: ChannelSocketState,
) -> mist.Next(ChannelSocketState, ChannelSocketMessage) {
  pubsub.subscribe(
    state.pubsub,
    state.channel_name,
    state.receiver,
    state.latest_event,
  )

  process.send_after(state.self, channel_socket_heartbeat_interval, Heartbeat)
  mist.continue(state)
}

fn channel_websocket_handle_vacuum(
  state: ChannelSocketState,
) -> mist.Next(ChannelSocketState, ChannelSocketMessage) {
  let state = case
    set.size(state.already_received) > max_already_received_size
  {
    True -> {
      let now =
        timestamp.system_time() |> timestamp.to_unix_seconds |> float.round
      let already_received =
        set.to_list(state.already_received)
        |> list.filter(fn(event) {
          let age = now - event.sequence_id
          age < already_received_keep_for
        })
        |> list.sort(fn(e1, e2) {
          int.compare(e1.sequence_id, e2.sequence_id) |> order.negate
        })
        |> list.take(post_vacuum_starting_size)
        |> set.from_list

      State(..state, already_received:)
    }
    False -> {
      let now =
        timestamp.system_time() |> timestamp.to_unix_seconds |> float.round
      let already_received =
        set.filter(state.already_received, fn(event) {
          let age = now - event.sequence_id
          age < already_received_keep_for
        })

      State(..state, already_received:)
    }
  }

  process.send_after(state.self, channel_vacuum_interval, Vacuum)
  mist.continue(state)
}

fn channel_websocket_handle_incoming_event(
  state: ChannelSocketState,
  event: channel.PubsubEvent,
  conn: mist.WebsocketConnection,
) -> mist.Next(ChannelSocketState, ChannelSocketMessage) {
  use <- bool.guard(
    when: set.contains(state.already_received, event),
    return: mist.continue(state),
  )

  let data = channel.encode_pubsub_event(event) |> json.to_string
  let assert Ok(_) = mist.send_text_frame(conn, data)

  let latest_event =
    state.latest_event
    |> option.map(int.max(_, event.sequence_id))
    |> option.unwrap(event.sequence_id)
    |> option.Some

  let already_received = set.insert(state.already_received, event)

  mist.continue(State(..state, latest_event:, already_received:))
}

fn channel_websocket_on_close(state: ChannelSocketState) -> Nil {
  pubsub.unsubscribe(
    state.pubsub,
    channel: state.channel_name,
    receiver: state.receiver,
  )
}
