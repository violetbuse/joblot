import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import joblot/pubsub/manager
import joblot/pubsub/server

pub type Message =
  manager.Message

pub fn supervised(name: process.Name(Message), port) {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(manager.supervised(name))
  |> supervisor.add(server.supervised(name, port))
  |> supervisor.supervised
}
