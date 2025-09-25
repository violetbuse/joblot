import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/http
import gleam/int
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import joblot/executor
import joblot/instance/attempts
import joblot/instance/sql
import joblot/lock
import joblot/utils
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
    process.send_after(subject, 1000, Heartbeat)

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
    one_off_job_id: String,
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

  use <- bool.guard(!has_lock, return: actor.continue(state))

  let #(job_data, attempts) = get_info(state)
  let should_retry = attempts.should_retry(attempts, job_data.maximum_attempts)

  let _ = case should_retry {
    attempts.CanRetry -> Nil
    _ -> {
      let assert Ok(_) =
        sql.set_one_off_job_complete(
          pog.named_connection(state.db),
          state.one_off_job_id,
        )
      Nil
    }
  }

  let not_successful_yet = should_retry == attempts.CanRetry
  let current_time = utils.get_unix_timestamp()
  let next_heartbeat_time =
    current_time
    + { { heartbeat_interval_ms / 2 } / 1000 }
    - { pre_heartbeat_buffer_ms / 1000 }
  let next_retry_time =
    attempts.next_retry_time(
      attempts,
      job_data.execute_at,
      initial_delay_seconds,
      factor,
      maximum_delay_seconds,
    )
  let should_execute =
    not_successful_yet && next_retry_time < next_heartbeat_time

  use <- bool.guard(!should_execute, return: actor.continue(state))

  let ms_to_execute = { next_retry_time - current_time } * 1000
  process.send_after(
    state.self,
    int.max(ms_to_execute, 0),
    Execute(job_data.execute_at, next_retry_time),
  )

  actor.continue(state)
}

fn handle_execute(
  state: State,
  for_planned_at: Int,
  for_try_at: Int,
) -> actor.Next(State, Message) {
  let has_lock = lock.has_lock(state.lock_manager, state.lock_id)

  use <- bool.guard(!has_lock, return: actor.continue(state))

  let #(job_data, attempts) = get_info(state)

  use <- bool.guard(
    job_data.execute_at != for_planned_at,
    return: actor.continue(state),
  )

  let retry_time =
    attempts.next_retry_time(
      attempts,
      job_data.execute_at,
      initial_delay_seconds,
      factor,
      maximum_delay_seconds,
    )

  let should_execute = retry_time == for_try_at

  use <- bool.guard(!should_execute, return: actor.continue(state))

  let request =
    executor.ExecutorRequest(
      method: job_data.method,
      url: job_data.url,
      headers: job_data.headers,
      body: job_data.body,
      timeout_ms: job_data.timeout_ms,
      non_2xx_is_failure: job_data.non_2xx_is_failure,
    )

  let current_time = utils.get_unix_timestamp()

  let execution_result = executor.execute_request(request)
  let save_data =
    attempts.AttemptSaveData(
      planned_at: job_data.execute_at,
      attempted_at: current_time,
      job_id: state.one_off_job_id,
      job_type: attempts.OneOffJob,
      user_id: job_data.user_id,
      tenant_id: job_data.tenant_id,
    )

  let assert Ok(_) = {
    let save_result =
      attempts.save_response(state.db, save_data, request, execution_result)
    save_result
  }

  actor.continue(state)
}

fn get_info(state: State) -> #(sql.GetOneOffJobRow, List(attempts.Attempt)) {
  let connection = pog.named_connection(state.db)
  let assert Ok(pog.Returned(_, [job_data_row])) =
    sql.get_one_off_job(connection, state.one_off_job_id)
  let assert Ok(attempts) =
    attempts.get_attempts_for_planned_at(
      state.db,
      state.one_off_job_id,
      job_data_row.execute_at,
    )
  #(job_data_row, attempts)
}
