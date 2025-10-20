import gleam/erlang/process
import gleam/otp/actor
import joblot/pubsub/types

type State {
  State(manager: process.Subject(types.ManagerMessage))
}

pub fn start(manager_name: process.Name(types.ManagerMessage)) {
  let manager = process.named_subject(manager_name)

  actor.new_with_initialiser(500, initialize(_, manager))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn initialize(
  self: process.Subject(types.ChannelMessage),
  manager: process.Subject(types.ManagerMessage),
) -> Result(actor.Initialised(State, types.ChannelMessage, Nil), String) {
  todo
}

fn handle_message(
  state: State,
  message: types.ChannelMessage,
) -> actor.Next(State, types.ChannelMessage) {
  todo
}
