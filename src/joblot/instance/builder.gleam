import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import joblot/executor
import joblot/instance/attempts
import joblot/lock
import joblot/utils
import pog

pub opaque type Builder {
  Builder(
    get_next_execution_time: Option(GetNextExecutionTime),
    get_next_request_data: Option(GetNextRequestData),
    post_execution_hook: Option(PostExecutionHook),
    heartbeat_interval_ms: Int,
    initial_delay_seconds: Int,
    factor: Float,
    maximum_delay_seconds: Int,
  )
}

pub type NextExecutionResult {
  NextExecutionResult(planned_at: Int, execute_at: Int)
}

pub type GetNextExecutionTime =
  fn(String, process.Name(pog.Message)) -> Result(NextExecutionResult, String)

pub type GetAttemptSaveData =
  fn(Int) -> attempts.AttemptSaveData

pub type NextRequestDataResult {
  NextRequestDataResult(
    request: executor.ExecutorRequest,
    get_attempt_save_data: GetAttemptSaveData,
  )
}

pub type GetNextRequestData =
  fn(String, process.Name(pog.Message)) -> Result(NextRequestDataResult, String)

pub type PostExecutionHook =
  fn(
    process.Name(pog.Message),
    executor.ExecutorRequest,
    Result(executor.ExecutorResponse, executor.ExecutorError),
  ) ->
    Result(Nil, String)

pub fn new() -> Builder {
  Builder(
    get_next_execution_time: None,
    get_next_request_data: None,
    post_execution_hook: None,
    heartbeat_interval_ms: 30_000,
    initial_delay_seconds: 60,
    factor: 1.5,
    maximum_delay_seconds: 86_400,
  )
}

pub fn next_execution_time(
  builder: Builder,
  next_execution_time: GetNextExecutionTime,
) -> Builder {
  Builder(..builder, get_next_execution_time: Some(next_execution_time))
}

pub fn next_request_data(
  builder: Builder,
  next_request_data: GetNextRequestData,
) -> Builder {
  Builder(..builder, get_next_request_data: Some(next_request_data))
}

pub fn post_execution_hook(
  builder: Builder,
  post_execution_hook: PostExecutionHook,
) -> Builder {
  Builder(..builder, post_execution_hook: Some(post_execution_hook))
}

pub fn heartbeat_interval_ms(
  builder: Builder,
  heartbeat_interval_ms: Int,
) -> Builder {
  Builder(..builder, heartbeat_interval_ms: heartbeat_interval_ms)
}

pub fn initial_delay_seconds(
  builder: Builder,
  initial_delay_seconds: Int,
) -> Builder {
  Builder(..builder, initial_delay_seconds: initial_delay_seconds)
}

pub fn factor(builder: Builder, factor: Float) -> Builder {
  Builder(..builder, factor: factor)
}

pub fn maximum_delay_seconds(
  builder: Builder,
  maximum_delay_seconds: Int,
) -> Builder {
  Builder(..builder, maximum_delay_seconds: maximum_delay_seconds)
}

type State {
  State(
    self: process.Subject(Message),
    db: process.Name(pog.Message),
    lock_manager: process.Name(lock.LockMgrMessage),
    id: String,
    lock_id: String,
    get_next_execution_time: GetNextExecutionTime,
    get_next_request_data: GetNextRequestData,
    post_execution_hook: PostExecutionHook,
    heartbeat_interval_ms: Int,
    initial_delay_seconds: Int,
    factor: Float,
    maximum_delay_seconds: Int,
  )
}

fn new_state(
  process_subject: process.Subject(Message),
  builder: Builder,
  id: String,
  lock_id: String,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
) -> State {
  let assert Some(get_next_execution_time) = builder.get_next_execution_time
  let assert Some(get_next_request_data) = builder.get_next_request_data
  let assert Some(post_execution_hook) = builder.post_execution_hook

  State(
    self: process_subject,
    db: db,
    lock_manager: lock_manager,
    id: id,
    lock_id: lock_id,
    get_next_execution_time: get_next_execution_time,
    get_next_request_data: get_next_request_data,
    post_execution_hook: post_execution_hook,
    heartbeat_interval_ms: builder.heartbeat_interval_ms,
    initial_delay_seconds: builder.initial_delay_seconds,
    factor: builder.factor,
    maximum_delay_seconds: builder.maximum_delay_seconds,
  )
}

type Message {
  Heartbeat
  Execute(for_planned_at: Int, for_try_at: Int)
}

pub fn start(
  builder: Builder,
  id: String,
  lock_id: String,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
) {
  actor.new_with_initialiser(1000, initializer(
    _,
    builder,
    id,
    lock_id,
    db,
    lock_manager,
  ))
  |> actor.on_message(handle_message)
  |> actor.start
}

pub fn supervised(
  builder: Builder,
  id: String,
  lock_id: String,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
) {
  supervision.worker(fn() { start(builder, id, lock_id, db, lock_manager) })
}

fn initializer(
  process_subject: process.Subject(Message),
  builder: Builder,
  id: String,
  lock_id: String,
  db: process.Name(pog.Message),
  lock_manager: process.Name(lock.LockMgrMessage),
) {
  new_state(process_subject, builder, id, lock_id, db, lock_manager)
  |> actor.initialised()
  |> actor.returning(Nil)
  |> Ok
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Heartbeat -> handle_heartbeat(state)
    Execute(for_planned_at, for_try_at) ->
      handle_execute(state, for_planned_at, for_try_at)
  }
}

fn handle_heartbeat(state: State) -> actor.Next(State, Message) {
  process.send_after(state.self, jitter_heartbeat_ms(state), Heartbeat)

  let has_lock = lock.has_lock(state.lock_manager, state.lock_id)

  use <- bool.guard(when: !has_lock, return: actor.continue(state))

  let assert Ok(next_execution_time) =
    state.get_next_execution_time(state.id, state.db)

  let within_next_tick =
    next_execution_time_within_tick(state, next_execution_time.execute_at)

  use <- bool.guard(when: !within_next_tick, return: actor.continue(state))

  let time_to_execution_ms =
    time_to_execution_ms(next_execution_time.execute_at)

  process.send_after(
    state.self,
    time_to_execution_ms,
    Execute(next_execution_time.planned_at, next_execution_time.execute_at),
  )

  actor.continue(state)
}

fn jitter_heartbeat_ms(state: State) -> Int {
  { int.to_float(state.heartbeat_interval_ms) *. { float.random() +. 0.5 } }
  |> float.round
}

fn next_execution_time_within_tick(
  state: State,
  next_execution_time: Int,
) -> Bool {
  let current_time = utils.get_unix_timestamp()
  let next_tick_time =
    current_time + { state.heartbeat_interval_ms / 1000 } - { 2000 / 1000 }
  next_execution_time <= next_tick_time
}

fn time_to_execution_ms(next_execution_time: Int) -> Int {
  let current_time = utils.get_unix_timestamp()
  let time_to_execution = { next_execution_time - current_time } * 1000
  int.max(time_to_execution, 500)
}

fn handle_execute(
  state: State,
  for_planned_at: Int,
  for_try_at: Int,
) -> actor.Next(State, Message) {
  let has_lock = lock.has_lock(state.lock_manager, state.lock_id)

  use <- bool.guard(when: !has_lock, return: actor.continue(state))

  let assert Ok(NextExecutionResult(planned_at, execute_at)) =
    state.get_next_execution_time(state.id, state.db)

  use <- bool.guard(
    when: planned_at != for_planned_at,
    return: actor.continue(state),
  )
  use <- bool.guard(
    when: execute_at != for_try_at,
    return: actor.continue(state),
  )

  let assert Ok(NextRequestDataResult(request, get_attempt_save_data)) =
    state.get_next_request_data(state.id, state.db)

  let current_time = utils.get_unix_timestamp()

  let execution_result = executor.execute_request(request)

  let save_data = get_attempt_save_data(current_time)

  let assert Ok(_) =
    attempts.save_response(state.db, save_data, request, execution_result)

  let assert Ok(_) =
    state.post_execution_hook(state.db, request, execution_result)

  actor.continue(state)
}
