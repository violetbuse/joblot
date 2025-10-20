import gleam/dict
import gleam/erlang/process
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/set
import joblot/pubsub/types

pub type Message =
  types.ManagerMessage

const heartbeat_interval_ms = 10_000

pub type State {
  State(
    self: process.Subject(Message),
    channels: dict.Dict(String, process.Subject(types.ChannelMessage)),
    servers: dict.Dict(
      reference.Reference,
      process.Subject(types.ServerMessage),
    ),
    clients: set.Set(process.Subject(types.ClientMessage)),
  )
}

pub fn supervised(name: process.Name(Message)) {
  supervision.worker(fn() {
    actor.new_with_initialiser(1000, initialize)
    |> actor.on_message(handle_message)
    |> actor.named(name)
    |> actor.start
  })
}

fn initialize(
  self: process.Subject(Message),
) -> Result(actor.Initialised(State, Message, Nil), String) {
  process.send(self, types.MgrHeartbeat)

  State(self:, channels: dict.new(), servers: dict.new(), clients: set.new())
  |> actor.initialised
  |> Ok
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    types.MgrHeartbeat -> handle_heartbeat(state)
    types.GetChannel(name, reply_with) ->
      handle_get_channel(name, reply_with, state)
    types.InitServer(ref, subject) -> handle_init_server(ref, subject, state)
    types.CloseServer(ref) -> handle_close_server(ref, state)
  }
}

fn handle_heartbeat(state: State) -> actor.Next(State, Message) {
  process.send_after(state.self, heartbeat_interval_ms, types.MgrHeartbeat)

  process.spawn(fn() {
    let state = state

    let server_connections =
      dict.values(state.servers)
      |> list.map(types.ServerConnection)
      |> set.from_list
    let client_connections = set.map(state.clients, types.ClientConnection)

    let connections = set.union(server_connections, client_connections)

    set.each(connections, fn(connection) {
      let set_without_connection = set.delete(connections, connection)
      let time_after = int.random(heartbeat_interval_ms / 2)

      case connection {
        types.ServerConnection(subject) ->
          process.send_after(
            subject,
            time_after,
            types.SrvHeartbeat(state.channels, set_without_connection),
          )
        types.ClientConnection(subject) ->
          process.send_after(
            subject,
            time_after,
            types.CltHeartbeat(state.channels, set_without_connection),
          )
      }
    })

    dict.each(state.channels, fn(_channel_id, channel_subject) {
      let time_after = int.random(heartbeat_interval_ms / 2)

      process.send_after(
        channel_subject,
        time_after,
        types.ChHeartbeat(connections),
      )
    })
  })

  actor.continue(state)
}

fn handle_get_channel(
  channel_name: String,
  respond_with: process.Subject(process.Subject(types.ChannelMessage)),
  state: State,
) -> actor.Next(State, Message) {
  todo
}

fn handle_init_server(
  ref: reference.Reference,
  subject: process.Subject(types.ServerMessage),
  state: State,
) -> actor.Next(State, Message) {
  actor.continue(
    State(..state, servers: dict.insert(state.servers, ref, subject)),
  )
}

fn handle_close_server(
  ref: reference.Reference,
  state: State,
) -> actor.Next(State, Message) {
  actor.continue(State(..state, servers: dict.delete(state.servers, ref)))
}
