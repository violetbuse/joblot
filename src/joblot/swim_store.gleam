import gleam/erlang/process
import gleam/otp/actor
import gleam/uri
import sqlight

pub type NodeInfo {
  NodeInfo(
    version: Int,
    state: NodeState,
    id: String,
    address: uri.Uri,
    region: String,
    shard_count: Int,
  )
}

pub type NodeState {
  Alive
  Suspect
  Dead
}

pub type SwimStore {
  SwimStore(subject: process.Subject(Message))
}

pub opaque type Message

type State {
  State(db: sqlight.Connection)
}

fn initialize(
  self: process.Subject(Message),
  datafile: String,
) -> Result(actor.Initialised(State, Message, SwimStore), String) {
  todo
}
