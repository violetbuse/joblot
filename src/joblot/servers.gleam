import gleam/erlang/process
import gleam/float
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/set
import gleam/time/timestamp
import joblot/servers/sql
import pog

const heartbeat_ms = 10_000

pub opaque type Message {
  Heartbeat
  GetOthers(reply_with: process.Subject(set.Set(String)))
}

type State {
  State(
    self: process.Subject(Message),
    db: process.Name(pog.Message),
    address: String,
    servers: set.Set(String),
  )
}

pub fn supervised(
  name: process.Name(Message),
  db: process.Name(pog.Message),
  address: String,
) {
  supervision.worker(fn() {
    actor.new_with_initialiser(2000, initialize(_, db, address))
    |> actor.on_message(handle_message)
    |> actor.named(name)
    |> actor.start
  })
}

fn initialize(
  self: process.Subject(Message),
  db: process.Name(pog.Message),
  address: String,
) -> Result(actor.Initialised(State, Message, Nil), String) {
  process.send(self, Heartbeat)

  let connection = pog.named_connection(db)

  let assert Ok(pog.Returned(_, rows)) = sql.list_servers(connection)

  list.map(rows, fn(row) { row.address })
  |> set.from_list
  |> State(self, db, address, _)
  |> actor.initialised
  |> Ok
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Heartbeat -> {
      let connection = pog.named_connection(state.db)
      let assert Ok(pog.Returned(_, rows)) = sql.list_servers(connection)

      let servers = list.map(rows, fn(row) { row.address }) |> set.from_list
      let current_time =
        timestamp.system_time() |> timestamp.to_unix_seconds |> float.round

      let assert Ok(_) =
        sql.update_server_time(connection, state.address, current_time)

      let older_than = current_time - heartbeat_ms * 3

      let assert Ok(_) = sql.delete_older_than(connection, older_than)

      State(..state, servers:)
      |> actor.continue
    }
    GetOthers(reply_with) -> {
      state.servers
      |> set.delete(state.address)
      |> process.send(reply_with, _)

      actor.continue(state)
    }
  }
}

pub fn get_others(process: process.Name(Message)) -> set.Set(String) {
  process.named_subject(process)
  |> process.call(1000, GetOthers)
}
