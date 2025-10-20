import gleam/erlang/process
import gleam/otp/actor
import joblot/pubsub/types

type State {
  State(manager: process.Subject(types.ManagerMessage), id: String)
}

pub fn start(manager_name: process.Name(types.ManagerMessage), id: String) {
  let manager = process.named_subject(manager_name)

  actor.new_with_initialiser(500, initialize(_, manager, id))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn initialize(
  self: process.Subject(types.ChannelMessage),
  manager: process.Subject(types.ManagerMessage),
  id: String,
) -> Result(
  actor.Initialised(
    State,
    types.ChannelMessage,
    process.Subject(types.ChannelMessage),
  ),
  String,
) {
  todo
}

fn handle_message(
  state: State,
  message: types.ChannelMessage,
) -> actor.Next(State, types.ChannelMessage) {
  todo
}
