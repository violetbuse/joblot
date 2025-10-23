import gleam/bool
import gleam/dict
import gleam/erlang/process
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/set
import joblot/pubsub/channel
import joblot/pubsub/client
import joblot/pubsub/types
import joblot/servers

pub type Message =
  types.ManagerMessage

const heartbeat_interval_ms = 10_000

pub type State {
  State(
    self: process.Subject(Message),
    self_name: process.Name(Message),
    server_registry: process.Name(servers.Message),
    channels: dict.Dict(String, process.Subject(types.ChannelMessage)),
    servers: dict.Dict(
      reference.Reference,
      process.Subject(types.ServerMessage),
    ),
    clients: dict.Dict(String, process.Subject(types.ClientMessage)),
  )
}

pub fn supervised(
  name: process.Name(Message),
  server_registry: process.Name(servers.Message),
) {
  supervision.worker(fn() {
    actor.new_with_initialiser(1000, initialize(_, name, server_registry))
    |> actor.on_message(handle_message)
    |> actor.named(name)
    |> actor.start
  })
}

fn initialize(
  self: process.Subject(Message),
  self_name: process.Name(Message),
  server_registry: process.Name(servers.Message),
) -> Result(actor.Initialised(State, Message, Nil), String) {
  process.send(self, types.MgrHeartbeat)

  State(
    self:,
    self_name:,
    server_registry: server_registry,
    channels: dict.new(),
    servers: dict.new(),
    clients: dict.new(),
  )
  |> actor.initialised
  |> Ok
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    types.MgrHeartbeat -> handle_heartbeat(state)
    types.GetChannel(name, reply_with) ->
      handle_get_channel(name, reply_with, state)
    types.RegisterServer(ref, subject) ->
      handle_register_server(ref, subject, state)
    types.CloseServer(ref) -> handle_close_server(ref, state)
    types.ClientAddresses(reply_with) ->
      handle_client_addresses(reply_with, state)
    types.RegisterClient(addr, subject) ->
      handle_register_client(addr, subject, state)
    types.CloseClient(addr) -> handle_close_client(addr, state)
    types.RegisterChannel(id, subject) ->
      handle_register_channel(id, subject, state)
  }
}

fn handle_heartbeat(state: State) -> actor.Next(State, Message) {
  process.send_after(state.self, heartbeat_interval_ms, types.MgrHeartbeat)

  process.spawn(fn() {
    let state = state

    dict.each(state.clients, fn(_address, client) {
      let time_after =
        int.random(heartbeat_interval_ms / 2) + heartbeat_interval_ms / 2
      process.send_after(client, time_after, types.CltHeartbeat(state.channels))
    })

    dict.each(state.servers, fn(_ref, server) {
      let time_after =
        int.random(heartbeat_interval_ms / 2) + heartbeat_interval_ms / 2
      process.send_after(server, time_after, types.SrvHeartbeat(state.channels))
    })

    let server_set = dict.values(state.servers) |> set.from_list

    dict.each(state.channels, fn(_channel_id, channel_subject) {
      let time_after = int.random(heartbeat_interval_ms / 2)

      process.send_after(
        channel_subject,
        time_after,
        types.ChHeartbeat(server_set),
      )
    })
  })

  state
  |> verify_channels
  |> verify_servers
  |> verify_clients
  |> actor.continue
}

fn verify_channels(state: State) -> State {
  State(
    ..state,
    channels: dict.map_values(state.channels, fn(id, subject) {
      let assert Ok(pid) = process.subject_owner(subject)
      let is_alive = process.is_alive(pid)

      case is_alive {
        True -> subject
        False -> {
          let assert Ok(start_result) = channel.start(state.self_name, id)
          start_result.data
        }
      }
    }),
  )
}

fn verify_servers(state: State) -> State {
  State(
    ..state,
    servers: dict.filter(state.servers, fn(_, subject) {
      let assert Ok(pid) = process.subject_owner(subject)

      process.is_alive(pid)
    }),
  )
}

fn verify_clients(state: State) -> State {
  let clients =
    state.clients
    |> dict.filter(fn(_, subject) {
      let assert Ok(pid) = process.subject_owner(subject)
      process.is_alive(pid)
    })

  let client_addresses = dict.keys(clients) |> set.from_list
  let addresses = servers.get_others(state.server_registry)

  let clients_to_create = set.difference(addresses, client_addresses)

  let clients_without_killed =
    clients
    |> dict.filter(fn(addr, subject) {
      let should_kill = set.contains(addresses, addr) |> bool.negate

      case should_kill {
        False -> True
        True -> {
          let assert Ok(pid) = process.subject_owner(subject)
          process.kill(pid)
          False
        }
      }
    })

  let new_clients =
    set.to_list(clients_to_create)
    |> list.fold(clients_without_killed, fn(dict, address) {
      let assert Ok(start_result) = client.start(address, state.self_name)
      dict.insert(dict, address, start_result.data)
    })

  State(..state, clients: new_clients)
}

fn handle_get_channel(
  channel_name: String,
  respond_with: process.Subject(process.Subject(types.ChannelMessage)),
  state: State,
) -> actor.Next(State, Message) {
  let #(channel, new_state) = {
    let dict_result = dict.get(state.channels, channel_name)
    let alive_channel =
      result.try(dict_result, fn(channel_subject) {
        let assert Ok(pid) = process.subject_owner(channel_subject)
        case process.is_alive(pid) {
          True -> Ok(channel_subject)
          False -> Error(Nil)
        }
      })

    case alive_channel {
      Ok(channel) -> #(channel, state)
      Error(_) -> {
        let assert Ok(new_channel) =
          channel.start(state.self_name, channel_name)
        let new_state =
          State(
            ..state,
            channels: dict.insert(
              state.channels,
              channel_name,
              new_channel.data,
            ),
          )
        #(new_channel.data, new_state)
      }
    }
  }

  process.send(respond_with, channel)

  actor.continue(new_state)
}

fn handle_register_server(
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

fn handle_client_addresses(
  reply_with: process.Subject(set.Set(String)),
  state: State,
) -> actor.Next(State, Message) {
  dict.keys(state.clients) |> set.from_list |> process.send(reply_with, _)

  actor.continue(state)
}

fn handle_register_client(
  address: String,
  subject: process.Subject(types.ClientMessage),
  state: State,
) -> actor.Next(State, Message) {
  State(..state, clients: dict.insert(state.clients, address, subject))
  |> actor.continue
}

fn handle_close_client(
  address: String,
  state: State,
) -> actor.Next(State, Message) {
  State(..state, clients: dict.delete(state.clients, address))
  |> actor.continue
}

fn handle_register_channel(
  channel_id: String,
  subject: process.Subject(types.ChannelMessage),
  state: State,
) -> actor.Next(State, Message) {
  State(..state, channels: dict.insert(state.channels, channel_id, subject))
  |> actor.continue
}
