import filepath
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
import joblot/event_store.{type Event, type EventStore}
import joblot/swim
import joblot/util
import mist

const heartbeat_interval = 30_000

pub type ChannelConfig {
  ChannelConfig(
    channel_name: String,
    swim: process.Subject(swim.Message),
    cluster_secret: String,
    data_dir: String,
  )
}

pub type Message {
  Heartbeat
  HandleRequest(req: request.Request(mist.Connection), recv: ResponseChannel)
  AnnouncedSequences(sequences: dict.Dict(String, Int), from: String)
  NewEvents(node: String, events: List(Event))
  PublishEvent(String, recv: process.Subject(Event))
  GetEventRange(from: Int, to: Int, recv: process.Subject(List(Event)))
  Subscribe(receiver: process.Subject(Event), replay_from: option.Option(Int))
  Unsubscribe(receiver: process.Subject(Event))
}

pub type ResponseChannel =
  process.Subject(response.Response(mist.ResponseData))

type State {
  State(
    channel_name: String,
    subject: process.Subject(Message),
    swim: process.Subject(swim.Message),
    store: dict.Dict(String, EventStore),
    subscribers: set.Set(process.Subject(Event)),
    cluster_secret: String,
    data_dir: String,
  )
}

fn ensure_store(state: State, node_id: String) -> #(EventStore, State) {
  let new_dict =
    dict.upsert(state.store, node_id, fn(existing) {
      case existing {
        option.None ->
          case
            event_store.start(filepath.join(
              state.data_dir,
              node_id <> ".events.db",
            ))
          {
            Ok(store) -> store
            Error(err) -> {
              echo err
              panic as "Error starting event store"
            }
          }
        option.Some(store) -> store
      }
    })

  let assert Ok(store) = dict.get(new_dict, node_id)
  #(store, State(..state, store: new_dict))
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
      store: dict.new(),
      cluster_secret: config.cluster_secret,
      subscribers: set.new(),
      data_dir: config.data_dir,
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
    GetEventRange(from:, to:, recv:) -> handle_get_range(state, from, to, recv)
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
        // let sequences =
        //   dict.map_values(state.event_buckets, fn(_, bucket) {
        //     case list.first(bucket) {
        //       Ok(event) -> event.sequence_id
        //       Error(_) -> 0
        //     }
        //   })
        //   |> dict.to_list
        //   |> list.sample(3)
        //   |> dict.from_list

        // let sequences =
        //   channel_datastore.get_buckets(state.datastore)
        //   |> list.map(fn(node_id) {
        //     case channel_datastore.get_latest_event(state.datastore, node_id) {
        //       option.None -> Error(Nil)
        //       option.Some(event) -> Ok(#(node_id, event.time))
        //     }
        //   })
        //   |> result.values
        //   |> list.sample(3)
        //   |> dict.from_list

        let sequences =
          dict.map_values(state.store, fn(_, store) {
            event_store.get_latest(store)
            |> result.map(fn(event) { event.time })
            |> result.unwrap(0)
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
      // let existing_sequence =
      //   dict.get(state.event_buckets, sequence_node_id)
      //   |> result.unwrap([])
      //   |> list.first()
      //   |> result.map(fn(event) { event.sequence_id })
      //   |> result.unwrap(0)

      // let existing_sequence =
      //   channel_datastore.get_latest_event(state.datastore, sequence_node_id)
      //   |> option.map(fn(event) { event.time })
      //   |> option.unwrap(0)

      let existing_sequence =
        dict.get(state.store, sequence_node_id)
        |> result.map(event_store.get_latest)
        |> result.flatten
        |> result.map(fn(event) { event.time })
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

fn util_disseminate_new_events(events: List(Event), state: State) {
  list.reverse(events)
  |> list.each(fn(event) { set.each(state.subscribers, process.send(_, event)) })
}

fn handle_new_events(
  state: State,
  node_id: String,
  new_events: List(Event),
) -> actor.Next(State, Message) {
  // let new_buckets =
  //   dict.upsert(state.event_buckets, node_id, fn(existing) {
  //     case existing {
  //       option.None | option.Some([]) -> {
  //         util_disseminate_new_events(new_events, state)
  //         new_events
  //       }
  //       option.Some([first, ..] as events) -> {
  //         let new_events =
  //           list.take_while(new_events, fn(event) {
  //             event.sequence_id > first.sequence_id
  //           })

  //         util_disseminate_new_events(new_events, state)

  //         list.append(new_events, events)
  //       }
  //     }
  //   })

  let #(store, state) = ensure_store(state, node_id)
  let inserted_events = event_store.write(store, new_events)

  util_disseminate_new_events(inserted_events, state)

  actor.continue(state)
}

fn handle_publish_event(
  state: State,
  event: String,
  recv: process.Subject(Event),
) -> actor.Next(State, Message) {
  let #(self_node, other_nodes) =
    process.call(state.swim, 1000, swim.GetClusterView)

  // let existing_sequence =
  //   dict.get(state.event_buckets, self_node.id)
  //   |> result.unwrap([])
  //   |> list.first()
  //   |> result.map(fn(event) { event.sequence_id })
  //   |> result.unwrap(0)

  // let existing_sequence =
  //   channel_datastore.get_latest_event(state.datastore, self_node.id)
  //   |> option.map(fn(event) { event.time })
  //   |> option.unwrap(0)

  let #(store, state) = ensure_store(state, self_node.id)
  let existing_time =
    event_store.get_latest(store)
    |> result.map(fn(event) { event.time })
    |> result.unwrap(0)

  let next_time =
    timestamp.system_time()
    |> timestamp.to_unix_seconds()
    |> float.round
    |> int.max(existing_time + 1)
  let pubsub_event = event_store.Event(time: next_time, data: event)

  // let new_buckets =
  //   dict.upsert(state.event_buckets, self_node.id, fn(existing) {
  //     case existing {
  //       option.None -> [pubsub_event]
  //       option.Some(events) -> [pubsub_event, ..events]
  //     }
  //   })

  // channel_datastore.write_events(state.datastore, self_node.id, [
  //   event_from_pubsub_event(pubsub_event),
  // ])

  let _ = event_store.write(store, [pubsub_event])

  set.each(state.subscribers, process.send(_, pubsub_event))

  process.spawn(fn() {
    list.filter(other_nodes, swim.is_alive)
    |> list.each(fn(target) {
      process.spawn(fn() {
        send_announce_sequence(
          target.address,
          state.cluster_secret,
          state.channel_name,
          dict.from_list([#(self_node.id, next_time)]),
          self_node.id,
        )
      })
    })
  })

  process.send(recv, pubsub_event)

  actor.continue(state)
}

fn handle_get_range(
  state: State,
  from: Int,
  to: Int,
  recv: process.Subject(List(Event)),
) -> actor.Next(State, Message) {
  let events =
    dict.values(state.store)
    |> list.map(event_store.get_range(_, from, to))
    |> list.interleave
    |> list.sort(fn(e1, e2) { int.compare(e1.time, e2.time) })

  process.send(recv, events)

  actor.continue(state)
}

fn handle_subscribe(
  state: State,
  receiver: process.Subject(Event),
  replay_from: option.Option(Int),
) -> actor.Next(State, Message) {
  // case replay_from {
  //   option.None -> Nil
  //   option.Some(replay_from) -> {
  //     dict.values(state.event_buckets)
  //     |> list.interleave
  //     |> list.filter(fn(event) { event.sequence_id >= replay_from })
  //     |> list.sort(fn(a, b) { int.compare(a.sequence_id, b.sequence_id) })
  //     |> list.each(process.send(receiver, _))
  //   }
  // }

  case replay_from {
    option.None -> Nil
    option.Some(replay_from) -> {
      // channel_datastore.get_buckets(state.datastore)
      // |> list.map(fn(node_id) {
      //   channel_datastore.get_events_past(state.datastore, node_id, replay_from)
      // })
      // |> list.interleave
      // |> list.sort(fn(a, b) { int.compare(a.time, b.time) })
      // |> list.map(pubsub_event_from_event)
      // |> list.each(process.send(receiver, _))

      dict.values(state.store)
      |> list.map(event_store.get_from(_, replay_from))
      |> list.interleave
      |> list.sort(fn(e1, e2) { int.compare(e1.time, e2.time) })
      |> list.each(process.send(receiver, _))
    }
  }

  let subscribers = set.insert(state.subscribers, receiver)
  actor.continue(State(..state, subscribers:))
}

fn handle_unsubscribe(state: State, receiver: process.Subject(Event)) {
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
  SequenceResponse(events: List(Event))
}

fn encode_sequence_response(response: SequenceResponse) -> json.Json {
  json.array(response.events, event_store.encode_event)
}

fn decode_sequence_response() -> decode.Decoder(SequenceResponse) {
  {
    use events <- decode.then(decode.list(event_store.decode_event()))

    decode.success(SequenceResponse(events:))
  }
}

fn handle_request_sequence(
  state: State,
  for_node: String,
  from_seq: Int,
  recv: ResponseChannel,
) -> actor.Next(State, Message) {
  // let sequence_response =
  //   dict.get(state.event_buckets, for_node)
  //   |> result.unwrap([])
  //   |> list.take_while(fn(event) { event.sequence_id > from_seq })
  //   |> SequenceResponse

  // let sequence_response =
  //   channel_datastore.get_events_past(state.datastore, for_node, from_seq)
  //   |> list.map(pubsub_event_from_event)
  //   |> SequenceResponse

  let #(store, state) = ensure_store(state, for_node)
  let sequence_response =
    event_store.get_from(store, from_seq) |> SequenceResponse

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
