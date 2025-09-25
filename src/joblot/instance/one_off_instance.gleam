import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervision
import joblot/lock
import pog

pub fn start(
  id: String,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
) {
  actor.new_with_initialiser(5000, fn(subject) {
    process.send(subject, Heartbeat)

    actor.initialised(State(subject, db, lock_manager, id))
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

pub fn supervised(
  id: String,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
) {
  supervision.worker(fn() { start(id, db, lock_manager) })
}

pub opaque type Message {
  Heartbeat
}

type State {
  State(
    self: process.Subject(Message),
    db: process.Name(pog.Message),
    lock_manager: process.Name(lock.LockMgrMessage),
    one_off_job_id: String,
  )
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Heartbeat -> {
      actor.continue(state)
    }
  }
}
