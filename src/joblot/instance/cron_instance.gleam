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
import joblot/executor
import joblot/instance/attempts
import joblot/instance/sql
import joblot/lock
import joblot/utils
import pog

const heartbeat_interval_ms = 25_000

const pre_heartbeat_buffer_ms = 500

/// initial retry delay in seconds (1 minute)
const initial_delay_seconds = 60

/// exponential retry factor
const factor = 1.5

/// maximum retry delay in seconds (24 hours)
const maximum_delay_seconds = 86_400

pub fn start(
  id: String,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
  lock_id: String,
) {
  actor.new_with_initialiser(5000, fn(subject) {
    let initial_heartbeat_delay_ms = 10_000.0 *. { float.random() +. 0.5 }
    process.send_after(
      subject,
      initial_heartbeat_delay_ms |> float.round,
      Heartbeat,
    )

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

  use <- bool.guard(when: !has_lock, return: actor.continue(state))

  let #(job_data, attempts) = get_info(state)
  let next_planned_at = get_next_planned_at(job_data, attempts)
  let next_execution_time =
    get_next_execution_time(state, job_data, next_planned_at)
  let should_execute = next_execution_time_within_tick(next_execution_time)
  use <- bool.guard(when: !should_execute, return: actor.continue(state))

  let current_time = utils.get_unix_timestamp()
  let ms_to_execute = { next_execution_time - current_time } * 1000

  process.send_after(
    state.self,
    int.max(ms_to_execute, 0),
    Execute(next_planned_at, next_execution_time),
  )

  actor.continue(state)
}

fn handle_execute(
  state: State,
  for_planned_at: Int,
  for_try_at: Int,
) -> actor.Next(State, Message) {
  let has_lock = lock.has_lock(state.lock_manager, state.lock_id)
  use <- bool.guard(when: !has_lock, return: actor.continue(state))

  let #(job_data, attempts) = get_info(state)
  let next_planned_at = get_next_planned_at(job_data, attempts)
  let next_execution_time =
    get_next_execution_time(state, job_data, next_planned_at)

  use <- bool.guard(
    when: for_planned_at != next_planned_at,
    return: actor.continue(state),
  )
  use <- bool.guard(
    when: for_try_at != next_execution_time,
    return: actor.continue(state),
  )

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
      planned_at: for_planned_at,
      attempted_at: current_time,
      job_id: state.cron_job_id,
      job_type: attempts.CronJob,
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

fn next_cron_occurrence(last_occurrence: Int, cron: String) -> Int {
  let last_timestamp = timestamp.from_unix_seconds(last_occurrence)
  let offset = duration.milliseconds(0)
  let assert Ok(cron_expression) = clockwork.from_string(cron)
  let next_occurrence =
    clockwork.next_occurrence(cron_expression, last_timestamp, offset)
  let unix_seconds = timestamp.to_unix_seconds_and_nanoseconds(next_occurrence)
  unix_seconds.0
}

fn get_next_planned_at(
  job_data: sql.GetCronJobRow,
  attempts: List(attempts.Attempt),
) -> Int {
  use <- bool.guard(
    when: list.is_empty(attempts),
    return: next_cron_occurrence(job_data.created_at, job_data.cron),
  )

  let should_retry = attempts.should_retry(attempts, job_data.maximum_attempts)

  let assert Ok(latest_attempt) = list.last(attempts)

  case should_retry {
    attempts.CanRetry -> latest_attempt.planned_at
    _ -> next_cron_occurrence(latest_attempt.planned_at, job_data.cron)
  }
}

fn get_next_execution_time(
  state: State,
  job_data: sql.GetCronJobRow,
  planned_at: Int,
) -> Int {
  let assert Ok(attempts) =
    attempts.get_attempts_for_planned_at(
      state.db,
      state.cron_job_id,
      planned_at,
    )
  let next_execution_time =
    attempts.next_retry_time(
      attempts,
      planned_at,
      initial_delay_seconds,
      factor,
      maximum_delay_seconds,
    )
  next_execution_time
}

fn next_execution_time_within_tick(execution_time: Int) -> Bool {
  let current_time = utils.get_unix_timestamp()
  let time_to_next_tick =
    current_time
    + { heartbeat_interval_ms / 1000 }
    - { pre_heartbeat_buffer_ms / 1000 }
  execution_time < time_to_next_tick
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
