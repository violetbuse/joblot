import gleam/bit_array
import gleam/bytes_tree
import gleam/dict
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/option
import gleam/result
import joblot/event_store.{type Event}
import joblot/pubsub
import joblot/subscriber
import joblot/util
import mist

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
        |> event_store.encode_event
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
  State(subscriber: subscriber.Subscriber)
}

type ChannelSocketMessage {
  IncomingEvent(Event)
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
  let receiver = process.new_subject()
  let assert Ok(subscriber) =
    subscriber.new(pubsub, channel_name, replay_from, receiver)

  let state = State(subscriber:)

  let selector =
    process.new_selector()
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
  let _ = subscriber.publish(state.subscriber, text)
  mist.continue(state)
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
    IncomingEvent(event) ->
      channel_websocket_handle_incoming_event(state, event, conn)
  }
}

fn channel_websocket_handle_incoming_event(
  state: ChannelSocketState,
  event: Event,
  conn: mist.WebsocketConnection,
) -> mist.Next(ChannelSocketState, ChannelSocketMessage) {
  let data =
    json.object([
      #("time", json.int(event.time)),
      #("message", json.string(event.data)),
    ])
    |> json.to_string

  case mist.send_text_frame(conn, data) {
    Error(_) ->
      mist.stop_abnormal("unable to send websocket frame for channel: " <> data)
    Ok(_) -> mist.continue(state)
  }
}

fn channel_websocket_on_close(state: ChannelSocketState) -> Nil {
  subscriber.unsubscribe(state.subscriber)
}
