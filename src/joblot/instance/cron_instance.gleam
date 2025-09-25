import clockwork
import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import joblot/instance/attempts
import joblot/instance/sql
import joblot/lock
import pog

const heartbeat_interval_ms = 30_000

const pre_heartbeat_buffer_ms = 5000

/// initial retry delay in seconds (1 minute)
const initial_delay_seconds = 60

/// exponential retry factor
const factor = 2.0

/// maximum retry delay in seconds (24 hours)
const maximum_delay_seconds = 86_400

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
  Execute(for_planned_at: Int, for_try_at: Int)
}

type State {
  State(
    self: process.Subject(Message),
    db: process.Name(pog.Message),
    lock_manager: process.Name(lock.LockMgrMessage),
    lock_id: String,
    cron_job_id: String,
  )
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Heartbeat -> handle_heartbeat(state)
    Execute(for_planned_at, for_try_at) ->
      handle_execute(state, for_planned_at, for_try_at)
  }
}

fn handle_heartbeat(state: State) -> actor.Next(State, Message) {
  let has_lock = lock.has_lock(state.lock_manager, state.lock_id)

  let next_heartbeat_time =
    { int.to_float(heartbeat_interval_ms) *. { float.random() +. 0.5 } }
    |> float.round
  process.send_after(state.self, next_heartbeat_time, Heartbeat)

  use <- bool.guard(!has_lock, actor.continue(state))

  let #(job_data, attempts) = get_info(state)

  todo as "handle heartbeat"
}

fn handle_execute(
  state: State,
  for_planned_at: Int,
  for_try_at: Int,
) -> actor.Next(State, Message) {
  todo as "handle execute"
}

fn get_info(state: State) -> #(sql.GetCronJobRow, List(attempts.Attempt)) {
  let connection = pog.named_connection(state.db)
  let assert Ok(pog.Returned(_, [job_data_row])) =
    sql.get_cron_job(connection, state.cron_job_id)
  let assert Ok(latest_planned_at) =
    attempts.latest_planned_at(state.db, state.cron_job_id)
  let assert Ok(attempts) =
    attempts.get_attempts_for_planned_at(
      state.db,
      state.cron_job_id,
      latest_planned_at,
    )
  #(job_data_row, attempts)
}
