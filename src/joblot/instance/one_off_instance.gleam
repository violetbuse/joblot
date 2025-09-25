import gleam/bool
import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import joblot/instance/attempts
import joblot/instance/sql
import joblot/lock
import pog

pub fn start(
  id: String,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
  lock_id: String,
) {
  actor.new_with_initialiser(5000, fn(subject) {
    process.send(subject, Heartbeat)

    actor.initialised(State(subject, db, lock_manager, lock_id, id))
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
  lock_id: String,
) {
  supervision.worker(fn() { start(id, db, lock_manager, lock_id) })
}

pub opaque type Message {
  Heartbeat
}

type State {
  State(
    self: process.Subject(Message),
    db: process.Name(pog.Message),
    lock_manager: process.Name(lock.LockMgrMessage),
    lock_id: String,
    one_off_job_id: String,
  )
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Heartbeat -> handle_heartbeat(state)
  }
}

fn handle_heartbeat(state: State) -> actor.Next(State, Message) {
  let has_lock = lock.has_lock(state.lock_manager, state.lock_id)
  let connection = pog.named_connection(state.db)

  use <- bool.guard(!has_lock, actor.continue(state))

  let assert Ok(#(job_data, attempts)) = {
    use pog.Returned(_, rows) <- result.try(sql.get_one_off_job(
      connection,
      state.one_off_job_id,
    ))

    let assert [job_data] = rows

    use attempts <- result.try(attempts.get_attempts_for_planned_at(
      state.db,
      state.one_off_job_id,
      job_data.execute_at,
    ))

    Ok(#(job_data, attempts))
  }

  todo as "handle one off instance heartbeat"
}
