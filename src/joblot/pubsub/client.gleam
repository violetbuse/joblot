import gleam/erlang/process
import gleam/otp/actor
import joblot/pubsub/types

pub type Message =
  types.ClientMessage

type State {
  State(manager: process.Subject(types.ManagerMessage))
}

pub fn start(address: String, manager_name: process.Name(types.ManagerMessage)) {
  let manager = process.named_subject(manager_name)

  actor.new_with_initialiser(5000, initialize(_, manager))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn initialize(
  self: process.Subject(Message),
  manager: process.Subject(types.ManagerMessage),
) -> Result(actor.Initialised(State, types.ClientMessage, Nil), String) {
  todo
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  todo
}
