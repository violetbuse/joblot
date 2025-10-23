import gleam/erlang/process
import gleam/erlang/reference
import gleam/http/request
import gleam/http/response
import gleam/option
import gleam/otp/actor
import glisten
import joblot/pubsub/types
import mist.{type Connection}

pub type State {
  State(
    manager: process.Subject(types.ManagerMessage),
    self: process.Subject(types.ServerMessage),
    ref: reference.Reference,
  )
}

fn init(
  self: process.Subject(types.ServerMessage),
  manager: process.Name(types.ManagerMessage),
) -> Result(actor.Initialised(State, types.ServerMessage, Nil), String) {
  todo
}

fn loop(
  state: State,
  message: types.ServerMessage,
  connection: mist.SSEConnection,
) {
  todo
}

pub fn handler(
  request: request.Request(Connection),
  manager: process.Name(types.ManagerMessage),
) -> response.Response(mist.ResponseData) {
  let initial_response = response.new(200)
  mist.server_sent_events(
    request,
    initial_response:,
    init: init(_, manager),
    loop: loop,
  )
}
