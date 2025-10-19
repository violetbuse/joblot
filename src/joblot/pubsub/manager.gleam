import gleam/dict
import gleam/erlang/process
import gleam/erlang/reference
import gleam/otp/actor
import gleam/otp/supervision
import gleam/set
import glisten
import joblot/pubsub/types

pub type Message =
  types.ManagerMessage

pub type State {
  State(
    self: process.Subject(Message),
    channels: dict.Dict(String, process.Subject(types.ChannelMessage)),
    servers: dict.Dict(
      reference.Reference,
      glisten.Connection(types.ServerMessage),
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
  todo
}
