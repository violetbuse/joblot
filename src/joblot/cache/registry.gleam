import gleam/dict
import gleam/erlang/process
import gleam/option
import gleam/otp/actor
import gleam/otp/supervision
import joblot/cache/builder
import pog

pub type Builder(datatype) {
  Builder(
    name: option.Option(process.Name(Message(datatype))),
    pubsub_category: option.Option(String),
    get_data: option.Option(builder.GetDataHook(datatype)),
    heartbeat_ms: Int,
  )
}

pub fn new() -> Builder(datatype) {
  Builder(
    name: option.None,
    pubsub_category: option.None,
    get_data: option.None,
    heartbeat_ms: 4 * 60 * 1000,
  )
}

pub fn name(
  builder: Builder(datatype),
  name: process.Name(Message(datatype)),
) -> Builder(datatype) {
  Builder(..builder, name: option.Some(name))
}

pub fn get_data(
  builder: Builder(datatype),
  get_data: builder.GetDataHook(datatype),
) -> Builder(datatype) {
  Builder(..builder, get_data: option.Some(get_data))
}

pub fn pubsub_category(
  builder: Builder(datatype),
  category: String,
) -> Builder(datatype) {
  Builder(..builder, pubsub_category: option.Some(category))
}

pub type Message(datatype) {
  Register(id: String, subject: process.Subject(builder.Message(datatype)))
  GetData(id: String, reply_with: process.Subject(option.Option(datatype)))
}

pub type State(datatype) {
  State(
    kv: dict.Dict(String, process.Subject(builder.Message(datatype))),
    name: process.Name(Message(datatype)),
    db: process.Name(pog.Message),
    pubsub_category: String,
    get_data: builder.GetDataHook(datatype),
    instance_heartbeat_ms: Int,
  )
}

fn heartbeat_hook(
  name: process.Name(Message(datatype)),
) -> builder.HeartbeatHook(datatype) {
  fn(state: builder.State(datatype)) {
    let _ =
      process.named_subject(name)
      |> process.send(Register(state.id, state.self))
    Ok(Nil)
  }
}

pub fn start(builder: Builder(datatype), db: process.Name(pog.Message)) {
  let assert option.Some(name) = builder.name
  let assert option.Some(pubsub_category) = builder.pubsub_category
  let assert option.Some(get_data) = builder.get_data
  let instance_heartbeat_ms = builder.heartbeat_ms

  State(
    kv: dict.new(),
    name:,
    pubsub_category:,
    get_data:,
    instance_heartbeat_ms:,
    db:,
  )
  |> actor.new()
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start
}

pub fn supervised(builder: Builder(datatype), db: process.Name(pog.Message)) {
  supervision.worker(fn() { start(builder, db) })
}

fn handle_message(
  state: State(datatype),
  message: Message(datatype),
) -> actor.Next(State(datatype), Message(datatype)) {
  case message {
    Register(id, subject) -> handle_register(id, subject, state)
    GetData(id, subject) -> handle_get_data(id, subject, state)
  }
}

fn handle_register(
  id: String,
  subject: process.Subject(builder.Message(datatype)),
  state: State(datatype),
) -> actor.Next(State(datatype), Message(datatype)) {
  State(
    ..state,
    kv: dict.upsert(state.kv, id, fn(existing) {
      case existing {
        option.None -> subject
        option.Some(existing) -> {
          let assert Ok(pid) = process.subject_owner(existing)
          process.kill(pid)

          subject
        }
      }
    }),
  )
  |> actor.continue
}

fn handle_get_data(
  id: String,
  reply_with: process.Subject(option.Option(datatype)),
  state: State(datatype),
) -> actor.Next(State(datatype), Message(datatype)) {
  let existing = dict.get(state.kv, id)

  let _ =
    process.spawn(fn() {
      let cache_instance = case existing {
        Ok(subject) -> subject
        Error(_) -> {
          let assert Ok(actor.Started(data: subject, ..)) =
            builder.new()
            |> builder.pubsub_category(state.pubsub_category)
            |> builder.get_data(state.get_data)
            |> builder.heartbeat_hook(heartbeat_hook(state.name))
            |> builder.heartbeat_ms(state.instance_heartbeat_ms)
            |> builder.start(id, state.db)

          subject
        }
      }

      process.send(cache_instance, builder.GetData(reply_with))
    })

  actor.continue(state)
}
