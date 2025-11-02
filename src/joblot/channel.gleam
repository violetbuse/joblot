import gleam/bytes_tree
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/float
import gleam/function
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/set
import gleam/time/timestamp
import gleam/uri
import joblot/swim
import joblot/util
import mist

const heartbeat_interval = 30_000

pub type ChannelConfig {
  ChannelConfig(
    channel_name: String,
    swim: process.Subject(swim.Message),
    cluster_secret: String,
  )
}

pub type Message {
  Heartbeat
  HandleRequest(req: request.Request(mist.Connection), recv: ResponseChannel)
  AnnouncedSequences(sequences: dict.Dict(String, Int), from: String)
  NewEvents(node: String, events: List(PubsubEvent))
  PublishEvent(String, recv: process.Subject(PubsubEvent))
  Subscribe(
    receiver: process.Subject(PubsubEvent),
    replay_from: option.Option(Int),
  )
  Unsubscribe(receiver: process.Subject(PubsubEvent))
}

pub type ResponseChannel =
  process.Subject(response.Response(mist.ResponseData))

type State {
  State(
    channel_name: String,
    subject: process.Subject(Message),
    swim: process.Subject(swim.Message),
    event_buckets: dict.Dict(String, List(PubsubEvent)),
    subscribers: set.Set(process.Subject(PubsubEvent)),
    cluster_secret: String,
  )
}

pub type PubsubEvent {
  PubsubEvent(sequence_id: Int, data: String)
}

pub fn encode_pubsub_event(event: PubsubEvent) -> json.Json {
  json.object([
    #("sequence_id", json.int(event.sequence_id)),
    #("data", json.string(event.data)),
  ])
}

fn decode_pubsub_event() -> decode.Decoder(PubsubEvent) {
  use sequence_id <- decode.field("sequence_id", decode.int)
  use data <- decode.field("data", decode.string)

  decode.success(PubsubEvent(sequence_id:, data:))
}

fn initialize(
  self: process.Subject(Message),
  config: ChannelConfig,
) -> Result(actor.Initialised(State, Message, process.Subject(Message)), String) {
  process.send(self, Heartbeat)

  let state =
    State(
      channel_name: config.channel_name,
      subject: self,
      swim: config.swim,
      event_buckets: dict.new(),
      cluster_secret: config.cluster_secret,
      subscribers: set.new(),
    )

  actor.initialised(state)
  |> actor.returning(self)
  |> Ok
}

fn on_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    HandleRequest(req:, recv:) -> handle_request(state, req, recv)
    Heartbeat -> handle_heartbeat(state)
    AnnouncedSequences(sequences:, from:) ->
      handle_announced_sequences(state, sequences, from)
    NewEvents(node:, events:) -> handle_new_events(state, node, events)
    PublishEvent(event, recv) -> handle_publish_event(state, event, recv)
    Subscribe(receiver:, replay_from:) ->
      handle_subscribe(state, receiver, replay_from)
    Unsubscribe(receiver:) -> handle_unsubscribe(state, receiver)
  }
}

fn handle_heartbeat(state: State) -> actor.Next(State, Message) {
  announce_sequences(state)

  process.send_after(state.subject, heartbeat_interval, Heartbeat)
  actor.continue(state)
}

fn announce_sequences(state: State) {
  process.spawn(fn() {
    let #(self, nodes) = process.call(state.swim, 1000, swim.GetClusterView)
    let candidates = list.filter(nodes, swim.is_alive) |> list.sample(3)

    list.each(candidates, fn(remote) {
      process.spawn(fn() {
        let sequences =
          dict.map_values(state.event_buckets, fn(_, bucket) {
            case list.first(bucket) {
              Ok(event) -> event.sequence_id
              Error(_) -> 0
            }
          })
          |> dict.to_list
          |> list.sample(3)
          |> dict.from_list

        send_announce_sequence(
          remote.address,
          state.cluster_secret,
          state.channel_name,
          sequences,
          self.id,
        )
      })
    })
  })
}

fn handle_announced_sequences(
  state: State,
  sequences: dict.Dict(String, Int),
  from: String,
) -> actor.Next(State, Message) {
  process.spawn(fn() {
    dict.each(sequences, fn(sequence_node_id, new_sequence) {
      let existing_sequence =
        dict.get(state.event_buckets, sequence_node_id)
        |> result.unwrap([])
        |> list.first()
        |> result.map(fn(event) { event.sequence_id })
        |> result.unwrap(0)

      let available_new_messages = new_sequence > existing_sequence

      case available_new_messages {
        False -> Nil
        True -> {
          let _ =
            process.spawn(fn() {
              let node = process.call(state.swim, 1000, swim.GetNode(from, _))
              use node <- result.try(option.to_result(node, Nil))

              use response <- result.try(send_request_sequence(
                node.address,
                state.cluster_secret,
                state.channel_name,
                sequence_node_id,
                existing_sequence,
              ))

              process.send(
                state.subject,
                NewEvents(events: response.events, node: node.id),
              )
              |> Ok
            })

          Nil
        }
      }
    })
  })

  actor.continue(state)
}

fn util_disseminate_new_events(events: List(PubsubEvent), state: State) {
  list.reverse(events)
  |> list.each(fn(event) { set.each(state.subscribers, process.send(_, event)) })
}

fn handle_new_events(
  state: State,
  node_id: String,
  new_events: List(PubsubEvent),
) -> actor.Next(State, Message) {
  let new_buckets =
    dict.upsert(state.event_buckets, node_id, fn(existing) {
      case existing {
        option.None | option.Some([]) -> {
          util_disseminate_new_events(new_events, state)
          new_events
        }
        option.Some([first, ..] as events) -> {
          let new_events =
            list.take_while(new_events, fn(event) {
              event.sequence_id > first.sequence_id
            })

          util_disseminate_new_events(new_events, state)

          list.append(new_events, events)
        }
      }
    })

  actor.continue(State(..state, event_buckets: new_buckets))
}

fn handle_publish_event(
  state: State,
  event: String,
  recv: process.Subject(PubsubEvent),
) -> actor.Next(State, Message) {
  let #(self_node, other_nodes) =
    process.call(state.swim, 1000, swim.GetClusterView)
  let existing_sequence =
    dict.get(state.event_buckets, self_node.id)
    |> result.unwrap([])
    |> list.first()
    |> result.map(fn(event) { event.sequence_id })
    |> result.unwrap(0)
  let next_sequence =
    timestamp.system_time()
    |> timestamp.to_unix_seconds()
    |> float.round
    |> int.max(existing_sequence + 1)
  let pubsub_event = PubsubEvent(sequence_id: next_sequence, data: event)

  let new_buckets =
    dict.upsert(state.event_buckets, self_node.id, fn(existing) {
      case existing {
        option.None -> [pubsub_event]
        option.Some(events) -> [pubsub_event, ..events]
      }
    })

  set.each(state.subscribers, process.send(_, pubsub_event))

  process.spawn(fn() {
    list.filter(other_nodes, swim.is_alive)
    |> list.each(fn(target) {
      process.spawn(fn() {
        send_announce_sequence(
          target.address,
          state.cluster_secret,
          state.channel_name,
          dict.from_list([#(self_node.id, next_sequence)]),
          self_node.id,
        )
      })
    })
  })

  process.send(recv, pubsub_event)

  actor.continue(State(..state, event_buckets: new_buckets))
}

fn handle_subscribe(
  state: State,
  receiver: process.Subject(PubsubEvent),
  replay_from: option.Option(Int),
) {
  case replay_from {
    option.None -> Nil
    option.Some(replay_from) -> {
      dict.values(state.event_buckets)
      |> list.interleave
      |> list.filter(fn(event) { event.sequence_id >= replay_from })
      |> list.sort(fn(a, b) { int.compare(a.sequence_id, b.sequence_id) })
      |> list.each(process.send(receiver, _))
    }
  }

  let subscribers = set.insert(state.subscribers, receiver)
  actor.continue(State(..state, subscribers:))
}

fn handle_unsubscribe(state: State, receiver: process.Subject(PubsubEvent)) {
  let subscribers = set.delete(state.subscribers, receiver)
  actor.continue(State(..state, subscribers:))
}

type Request {
  AnnounceSequence(sequences: dict.Dict(String, Int), from: String)
  RequestSequence(for_node: String, from_seq: Int)
}

fn encode_request(request: Request) -> json.Json {
  case request {
    AnnounceSequence(sequences, from) ->
      json.object([
        #("type", json.string("announce_sequence")),
        #("sequences", json.dict(sequences, function.identity, json.int)),
        #("from", json.string(from)),
      ])
    RequestSequence(for_node:, from_seq:) ->
      json.object([
        #("type", json.string("request_sequence")),
        #("for_node", json.string(for_node)),
        #("from_seq", json.int(from_seq)),
      ])
  }
}

fn decode_request() -> decode.Decoder(Request) {
  let announce_sequence_decoder = {
    use sequences <- decode.field(
      "sequences",
      decode.dict(decode.string, decode.int),
    )
    use from <- decode.field("from", decode.string)

    decode.success(AnnounceSequence(sequences:, from:))
  }

  let request_sequence_decoder = {
    use for_node <- decode.field("for_node", decode.string)
    use from_seq <- decode.field("from_seq", decode.int)

    decode.success(RequestSequence(for_node: for_node, from_seq: from_seq))
  }

  {
    use tag <- decode.field("type", decode.string)

    case tag {
      "announce_sequence" -> announce_sequence_decoder
      "request_sequence" -> request_sequence_decoder
      _ ->
        decode.failure(
          AnnounceSequence(dict.new(), ""),
          "ValidChannelRequestType",
        )
    }
  }
}

const one_gb = 1_099_511_627_776

fn handle_request(
  state: State,
  req: request.Request(mist.Connection),
  recv: ResponseChannel,
) -> actor.Next(State, Message) {
  let assert Ok(req) = mist.read_body(req, one_gb)
  case json.parse_bits(req.body, decode_request()) {
    Error(_) -> {
      io.println_error("Invalid incoming channel request.")
      let body =
        json.object([#("error", json.string("Invalid channel request"))])
        |> json.to_string_tree
        |> bytes_tree.from_string_tree
        |> mist.Bytes

      let response = response.new(400) |> response.set_body(body)

      process.send(recv, response)

      actor.continue(state)
    }
    Ok(request) ->
      case request {
        AnnounceSequence(sequences:, from:) ->
          handle_announce_sequence(state, sequences, from, recv)
        RequestSequence(for_node:, from_seq:) ->
          handle_request_sequence(state, for_node, from_seq, recv)
      }
  }
}

fn handle_announce_sequence(
  state: State,
  sequences: dict.Dict(String, Int),
  from: String,
  recv: ResponseChannel,
) -> actor.Next(State, Message) {
  process.send(state.subject, AnnouncedSequences(sequences:, from:))

  let data =
    json.null()
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  let response = response.new(200) |> response.set_body(data)

  process.send(recv, response)
  actor.continue(state)
}

fn send_announce_sequence(
  api_address: uri.Uri,
  secret: String,
  channel_name: String,
  sequences: dict.Dict(String, Int),
  from: String,
) -> Result(Nil, Nil) {
  let data =
    AnnounceSequence(sequences:, from:) |> encode_request |> json.to_string
  let path = "/pubsub/channel/" <> channel_name

  let assert option.Some(host) = api_address.host

  use _response <- result.try(
    util.send_internal_request(api_address, secret, path, data)
    |> util.log_error("Error announcing sequence to " <> host)
    |> result.replace_error(Nil),
  )

  Ok(Nil)
}

type SequenceResponse {
  SequenceResponse(events: List(PubsubEvent))
}

fn encode_sequence_response(response: SequenceResponse) -> json.Json {
  json.array(response.events, encode_pubsub_event)
}

fn decode_sequence_response() -> decode.Decoder(SequenceResponse) {
  {
    use events <- decode.then(decode.list(decode_pubsub_event()))

    decode.success(SequenceResponse(events:))
  }
}

fn handle_request_sequence(
  state: State,
  for_node: String,
  from_seq: Int,
  recv: ResponseChannel,
) -> actor.Next(State, Message) {
  let sequence_response =
    dict.get(state.event_buckets, for_node)
    |> result.unwrap([])
    |> list.take_while(fn(event) { event.sequence_id > from_seq })
    |> SequenceResponse

  let data =
    encode_sequence_response(sequence_response)
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  let response = response.new(200) |> response.set_body(data)

  process.send(recv, response)

  actor.continue(state)
}

fn send_request_sequence(
  api_address: uri.Uri,
  secret: String,
  channel_name: String,
  for_node: String,
  from_seq: Int,
) -> Result(SequenceResponse, Nil) {
  let data =
    RequestSequence(for_node:, from_seq:) |> encode_request |> json.to_string
  let path = "/pubsub/channel/" <> channel_name

  let assert option.Some(host) = api_address.host

  use response <- result.try(
    util.send_internal_request(api_address, secret, path, data)
    |> util.log_error(
      "Error getting sequence from "
      <> host
      <> " for node "
      <> for_node
      <> " from sequence "
      <> int.to_string(from_seq),
    )
    |> result.replace_error(Nil),
  )

  use request_sequence_response <- result.try(
    json.parse(response.body, decode_sequence_response())
    |> util.log_error(
      "Error parsing request sequence response from "
      <> host
      <> ": "
      <> response.body,
    )
    |> result.replace_error(Nil),
  )

  Ok(request_sequence_response)
}

pub fn start(config: ChannelConfig) {
  actor.new_with_initialiser(1000, initialize(_, config))
  |> actor.on_message(on_message)
  |> actor.start
}
