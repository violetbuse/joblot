import gleam/erlang/process
import gleam/erlang/reference
import gleam/option
import glisten
import joblot/pubsub/types

pub type State {
  State(
    manager: process.Subject(types.ManagerMessage),
    self: process.Subject(types.ServerMessage),
    ref: reference.Reference,
  )
}

pub fn supervised(manager: process.Name(types.ManagerMessage), port: Int) {
  glisten.new(on_init(_, manager), loop)
  |> glisten.with_close(on_close)
  |> glisten.bind("0.0.0.0")
  |> glisten.with_ipv6
  |> glisten.supervised(port)
}

fn on_init(
  conn: glisten.Connection(types.ServerMessage),
  manager: process.Name(types.ManagerMessage),
) -> #(State, option.Option(process.Selector(types.ServerMessage))) {
  let self = process.new_subject()
  let selector = process.new_selector() |> process.select(self)

  process.send(self, types.SrvRefresh)

  let state =
    State(manager: process.named_subject(manager), self:, ref: reference.new())

  process.send(state.manager, types.InitServer(state.ref, state.self))

  #(state, option.Some(selector))
}

fn loop(
  state: State,
  message: glisten.Message(types.ServerMessage),
  connection: glisten.Connection(types.ServerMessage),
) -> glisten.Next(State, glisten.Message(types.ServerMessage)) {
  todo
}

fn on_close(state: State) -> Nil {
  process.send(state.manager, types.CloseServer(state.ref))
}
