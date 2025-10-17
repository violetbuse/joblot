import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/option
import gleam/otp/actor
import gleam/otp/supervision
import pog

pub opaque type Builder(datatype) {
  Builder(
    pubsub_category: option.Option(String),
    get_data: option.Option(GetDataHook(datatype)),
    heartbeat_hook: option.Option(HeartbeatHook(datatype)),
    heartbeat_ms: Int,
  )
}

pub type Context {
  Context(db: process.Name(pog.Message))
}

pub type GetDataHook(datatype) =
  fn(String, Context) -> Result(datatype, String)

pub type HeartbeatHook(datatype) =
  fn(State(datatype)) -> Result(Nil, Nil)

pub fn new() -> Builder(datatype) {
  Builder(
    pubsub_category: option.None,
    get_data: option.None,
    heartbeat_hook: option.None,
    heartbeat_ms: 4 * 60 * 1000,
  )
}

pub fn get_data(
  builder: Builder(datatype),
  get_data: GetDataHook(datatype),
) -> Builder(datatype) {
  Builder(..builder, get_data: option.Some(get_data))
}

pub fn heartbeat_hook(
  builder: Builder(datatype),
  heartbeat_hook: HeartbeatHook(datatype),
) -> Builder(datatype) {
  Builder(..builder, heartbeat_hook: option.Some(heartbeat_hook))
}

pub fn pubsub_category(
  builder: Builder(datatype),
  category: String,
) -> Builder(datatype) {
  Builder(..builder, pubsub_category: option.Some(category))
}

pub fn heartbeat_ms(
  builder: Builder(datatype),
  ms heartbeat: Int,
) -> Builder(datatype) {
  Builder(..builder, heartbeat_ms: heartbeat)
}

pub type State(datatype) {
  State(
    self: process.Subject(Message(datatype)),
    heartbeat_ms: Int,
    get_data: GetDataHook(datatype),
    heartbeat_hook: HeartbeatHook(datatype),
    id: String,
    context: Context,
    data: datatype,
  )
}

fn new_state(
  process_subject: process.Subject(Message(datatype)),
  builder: Builder(datatype),
  id: String,
  db: process.Name(pog.Message),
) -> State(datatype) {
  let assert option.Some(_pubsub_category) = builder.pubsub_category
  let assert option.Some(get_data_hook) = builder.get_data
  let assert option.Some(heartbeat_hook) = builder.heartbeat_hook

  let context = Context(db)

  let assert Ok(data) = get_data_hook(id, context)

  let state =
    State(
      self: process_subject,
      heartbeat_ms: builder.heartbeat_ms,
      get_data: get_data_hook,
      heartbeat_hook: heartbeat_hook,
      id: id,
      context: context,
      data: data,
    )

  let assert Ok(_) = heartbeat_hook(state)

  state
}

pub fn start(
  builder: Builder(datatype),
  id: String,
  db: process.Name(pog.Message),
) {
  actor.new_with_initialiser(5000, initializer(_, builder, id, db))
  |> actor.on_message(handle_message)
  |> actor.start
}

pub fn supervised(
  builder: Builder(datatype),
  id: String,
  db: process.Name(pog.Message),
) {
  supervision.worker(fn() { start(builder, id, db) })
}

fn initializer(
  process_subject: process.Subject(Message(datatype)),
  builder: Builder(datatype),
  id: String,
  db: process.Name(pog.Message),
) {
  let state = new_state(process_subject, builder, id, db)

  process.send_after(state.self, jitter_heartbeat_ms(state), Heartbeat)

  state
  |> actor.initialised
  |> actor.returning(process_subject)
  |> Ok
}

fn jitter_heartbeat_ms(state: State(datatype)) -> Int {
  { int.to_float(state.heartbeat_ms) *. { float.random() +. 0.5 } }
  |> float.round
  |> int.min(state.heartbeat_ms)
}

pub type Message(datatype) {
  GetData(reply_with: process.Subject(option.Option(datatype)))
  Heartbeat
  Refresh
}

fn handle_message(
  state: State(datatype),
  message: Message(datatype),
) -> actor.Next(State(datatype), Message(datatype)) {
  case message {
    GetData(reply_with) -> handle_get_data(reply_with, state, message)
    Heartbeat -> handle_heartbeat(state, message)
    Refresh -> handle_refresh(state, message)
  }
}

fn handle_get_data(
  reply_with: process.Subject(option.Option(datatype)),
  state: State(datatype),
  _message: Message(datatype),
) -> actor.Next(State(datatype), Message(datatype)) {
  process.send(reply_with, option.Some(state.data))
  actor.continue(state)
}

fn handle_heartbeat(
  state: State(datatype),
  _message: Message(datatype),
) -> actor.Next(State(datatype), Message(datatype)) {
  process.send_after(state.self, jitter_heartbeat_ms(state), Heartbeat)
  process.send(state.self, Refresh)

  let assert Ok(_) = state.heartbeat_hook(state)

  actor.continue(state)
}

fn handle_refresh(
  state: State(datatype),
  _message: Message(datatype),
) -> actor.Next(State(datatype), Message(datatype)) {
  case state.get_data(state.id, state.context) {
    Ok(data) -> {
      State(..state, data:)
      |> actor.continue
    }
    Error(_) -> actor.stop()
  }
}
