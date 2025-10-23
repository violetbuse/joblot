import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import joblot/pubsub/manager
import joblot/pubsub/server
import joblot/servers

pub type Message =
  manager.Message

pub fn supervised(
  name: process.Name(Message),
  servers: process.Name(servers.Message),
) {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(manager.supervised(name, servers))
  |> supervisor.supervised
}
