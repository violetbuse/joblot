import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervision
import gleam/time/timestamp
import joblot/sql
import pog

const clear_locks_interval = 10_000

pub fn start_lock_manager(
  name: process.Name(Message),
  db: process.Name(pog.Message),
) {
  actor.new_with_initialiser(5000, fn(subject) {
    actor.initialised(State(subject, db))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start
}

pub fn supervised(name: process.Name(Message), db: process.Name(pog.Message)) {
  supervision.worker(fn() { start_lock_manager(name, db) })
}

type State {
  State(self: process.Subject(Message), db: process.Name(pog.Message))
}

pub opaque type Message {
  Heartbeat
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Heartbeat -> {
      process.send_after(state.self, clear_locks_interval, Heartbeat)

      let #(current_time, _) =
        timestamp.system_time()
        |> timestamp.to_unix_seconds_and_nanoseconds

      let connection = pog.named_connection(state.db)
      let clear_locks_result = sql.clear_locks(connection, current_time)

      case clear_locks_result {
        Ok(_) -> {
          actor.continue(state)
        }
        Error(_) -> {
          actor.stop_abnormal("Failed to clear locks")
        }
      }
    }
  }
}
