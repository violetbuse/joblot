import filepath
import gleam/bytes_tree
import gleam/dict
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision
import gleam/result
import joblot/channel
import joblot/event_store.{type Event}
import joblot/swim
import mist
import simplifile

const heartbeat_interval = 5000

pub type PubsubConfig {
  PubsubConfig(
    name: process.Name(Message),
    swim: process.Subject(swim.Message),
    cluster_secret: String,
    data_dir: String,
  )
}

pub type Message {
  Heartbeat
  HandleRequest(
    req: request.Request(mist.Connection),
    response: ResponseChannel,
  )
  RegisterChannel(channel_id: String, channel: process.Subject(channel.Message))
  GetChannel(
    channel_id: String,
    recv: process.Subject(process.Subject(channel.Message)),
  )
}

pub type ResponseChannel =
  process.Subject(response.Response(mist.ResponseData))

type State {
  State(
    subject: process.Subject(Message),
    factory: factory_supervisor.Supervisor(
      String,
      process.Subject(channel.Message),
    ),
    register_new_channel: process.Subject(
      #(String, process.Subject(channel.Message)),
    ),
    channels: dict.Dict(String, process.Subject(channel.Message)),
    swim: process.Subject(swim.Message),
    cluster_secret: String,
  )
}

fn initialize(
  self: process.Subject(Message),
  config: PubsubConfig,
) -> Result(actor.Initialised(State, Message, Nil), String) {
  let register_channel = process.new_subject()

  let assert Ok(_) = simplifile.create_directory_all(config.data_dir)
    as "could not create pubsub directory"
  let assert Ok(channels) = simplifile.read_directory(config.data_dir)

  process.spawn_unlinked(fn() {
    list.each(channels, fn(channel_name) {
      process.send(self, GetChannel(channel_name, process.new_subject()))
    })
  })

  let assert Ok(factory_supervisor) =
    factory_supervisor.worker_child(fn(channel_id) {
      let data_dir = filepath.join(config.data_dir, "/" <> channel_id)

      let assert Ok(_) = simplifile.create_directory_all(data_dir)

      let start_result =
        channel.start(channel.ChannelConfig(
          channel_name: channel_id,
          swim: config.swim,
          cluster_secret: config.cluster_secret,
          data_dir:,
        ))

      let _ =
        result.map(start_result, fn(start_result) {
          process.send(
            self,
            RegisterChannel(channel_id:, channel: start_result.data),
          )
        })

      start_result
    })
    |> factory_supervisor.start

  let state =
    State(
      subject: self,
      factory: factory_supervisor.data,
      register_new_channel: register_channel,
      channels: dict.new(),
      swim: config.swim,
      cluster_secret: config.cluster_secret,
    )

  let selector =
    process.new_selector()
    |> process.select(self)
    |> process.select_map(register_channel, fn(event) {
      RegisterChannel(event.0, event.1)
    })

  actor.initialised(state)
  |> actor.selecting(selector)
  |> Ok
}

fn on_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    HandleRequest(req:, response:) -> handle_request(state, req, response)
    Heartbeat -> handle_heartbeat(state)
    RegisterChannel(channel_id:, channel:) ->
      handle_register_channel(state, channel_id, channel)
    GetChannel(channel_id:, recv:) ->
      handle_get_channel(state, channel_id, recv)
  }
}

fn util_get_channel(
  state: State,
  channel_id: String,
) -> #(process.Subject(channel.Message), Bool) {
  case dict.get(state.channels, channel_id) {
    Ok(channel_subject) -> #(channel_subject, False)
    Error(_) ->
      case factory_supervisor.start_child(state.factory, channel_id) {
        Ok(start_result) -> #(start_result.data, True)
        Error(_) -> panic as "Pubsub manager could not start child"
      }
  }
}

// const one_gb = 1_099_511_627_776

fn error_response() {
  let body =
    json.object([#("error", json.string("Invalid pubsub request."))])
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> mist.Bytes

  response.new(400) |> response.set_body(body)
}

fn handle_request(
  state: State,
  req: request.Request(mist.Connection),
  recv: ResponseChannel,
) -> actor.Next(State, Message) {
  case request.path_segments(req) {
    ["pubsub", "channel", channel_name, ..] -> {
      let #(channel_subject, had_to_create) =
        util_get_channel(state, channel_name)

      process.send(channel_subject, channel.HandleRequest(req, recv))

      let new_channels = case had_to_create {
        True -> dict.insert(state.channels, channel_name, channel_subject)
        False -> state.channels
      }

      actor.continue(State(..state, channels: new_channels))
    }
    _ -> {
      process.send(recv, error_response())
      actor.continue(state)
    }
  }
}

fn handle_get_channel(
  state: State,
  channel_id: String,
  recv: process.Subject(process.Subject(channel.Message)),
) -> actor.Next(State, Message) {
  let #(channel_subject, had_to_create) = util_get_channel(state, channel_id)

  process.send(recv, channel_subject)

  let new_channels = case had_to_create {
    True -> dict.insert(state.channels, channel_id, channel_subject)
    False -> state.channels
  }

  actor.continue(State(..state, channels: new_channels))
}

fn handle_heartbeat(state: State) -> actor.Next(State, Message) {
  process.send_after(state.subject, heartbeat_interval, Heartbeat)
  actor.continue(state)
}

fn handle_register_channel(
  state: State,
  channel_id: String,
  channel: process.Subject(channel.Message),
) -> actor.Next(State, Message) {
  let new_channels = dict.insert(state.channels, channel_id, channel)
  actor.continue(State(..state, channels: new_channels))
}

pub fn supervised(config: PubsubConfig) {
  supervision.worker(fn() {
    actor.new_with_initialiser(1000, initialize(_, config))
    |> actor.on_message(on_message)
    |> actor.named(config.name)
    |> actor.start
  })
}

pub fn publish(
  pubsub: process.Subject(Message),
  channel name: String,
  event data: String,
) {
  process.call(pubsub, 1000, GetChannel(name, _))
  |> process.call(1000, channel.PublishEvent(data, _))
}

pub fn range(
  pubsub: process.Subject(Message),
  channel name: String,
  from from: Int,
  until to: Int,
) {
  process.call(pubsub, 1000, GetChannel(name, _))
  |> process.call(1000, channel.GetEventRange(from, to, _))
}

pub fn subscribe(
  pubsub: process.Subject(Message),
  channel name: String,
  receive to: process.Subject(Event),
  replay from: option.Option(Int),
) {
  process.call(pubsub, 1000, GetChannel(name, _))
  |> process.send(channel.Subscribe(to, from))
}

pub fn unsubscribe(
  pubsub: process.Subject(Message),
  channel name: String,
  receiver recv: process.Subject(Event),
) {
  process.call(pubsub, 1000, GetChannel(name, _))
  |> process.send(channel.Unsubscribe(recv))
}
