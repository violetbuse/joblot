import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/result
import joblot/util
import sqlight

pub type Event {
  Event(time: Int, data: String)
}

pub fn encode_event(event: Event) -> json.Json {
  json.object([
    #("time", json.int(event.time)),
    #("data", json.string(event.data)),
  ])
}

pub fn decode_event() -> decode.Decoder(Event) {
  {
    use time <- decode.field("time", decode.int)
    use data <- decode.field("data", decode.string)

    decode.success(Event(time:, data:))
  }
}

pub type EventStore {
  EventStore(subject: process.Subject(Message))
}

pub opaque type Message {
  Close
  GetLatest(recv: process.Subject(Result(Event, Nil)))
  GetFrom(from: Int, recv: process.Subject(List(Event)))
  Write(events: List(Event), recv: process.Subject(List(Event)))
}

type State {
  State(db: sqlight.Connection)
}

fn with_pragma(
  value: String,
  connection: sqlight.Connection,
  cb: fn() -> Result(a, String),
) -> Result(a, String) {
  use _ <- result.try(
    sqlight.exec("PRAGMA " <> value <> ";", connection)
    |> result.replace_error("Could not set pragma: " <> value),
  )

  cb()
}

fn initialize(
  self: process.Subject(Message),
  datafile: String,
) -> Result(actor.Initialised(State, Message, EventStore), String) {
  use db <- result.try(
    sqlight.open(datafile)
    |> util.log_error("Could not open data file " <> datafile)
    |> result.replace_error("Could not open sqlite file " <> datafile),
  )

  use <- with_pragma("journal_mode = WAL", db)
  use <- with_pragma("busy_timeout = 5000", db)
  use <- with_pragma("synchronous = NORMAL", db)
  use <- with_pragma("cache_size = 1000000000", db)
  use <- with_pragma("foreign_keys = true", db)
  use <- with_pragma("temp_store = memory", db)

  use _ <- result.try(
    sqlight.exec(
      "
    CREATE TABLE IF NOT EXISTS events (
      time INTEGER PRIMARY KEY,
      data TEXT
    ) STRICT;
    ",
      db,
    )
    |> util.log_error("error running migrations")
    |> result.replace_error("could not run migrations"),
  )

  actor.initialised(State(db:))
  |> actor.returning(EventStore(self))
  |> Ok
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Close -> handle_close(state)
    GetFrom(from:, recv:) -> handle_get_from(state, from, recv)
    GetLatest(recv:) -> handle_get_latest(state, recv)
    Write(events:, recv:) -> handle_write(state, events, recv)
  }
}

fn handle_close(state: State) -> actor.Next(State, Message) {
  let assert Ok(_) = sqlight.close(state.db)
  actor.stop()
}

fn handle_get_latest(
  state: State,
  recv: process.Subject(Result(Event, Nil)),
) -> actor.Next(State, Message) {
  let latest = {
    let decoder = {
      use time <- decode.field(0, decode.int)
      use data <- decode.field(1, decode.string)
      decode.success(Event(time:, data:))
    }

    let sql =
      "
      SELECT time, data FROM events ORDER BY time DESC LIMIT 1;
    "

    let assert Ok(list) =
      sqlight.query(sql, on: state.db, with: [], expecting: decoder)

    list.first(list)
  }

  process.send(recv, latest)

  actor.continue(state)
}

fn handle_get_from(
  state: State,
  from: Int,
  recv: process.Subject(List(Event)),
) -> actor.Next(State, Message) {
  let result_set = {
    let decoder = {
      use time <- decode.field(0, decode.int)
      use data <- decode.field(1, decode.string)
      decode.success(Event(time:, data:))
    }

    let sql =
      "
    SELECT time, data FROM events
    WHERE time > ?
    ORDER BY time ASC;
    "

    let assert Ok(list) =
      sqlight.query(
        sql,
        on: state.db,
        with: [sqlight.int(from)],
        expecting: decoder,
      )

    list
  }

  process.send(recv, result_set)

  actor.continue(state)
}

fn with_transaction(
  db: sqlight.Connection,
  cb: fn(sqlight.Connection) -> Result(a, sqlight.Error),
) -> Result(a, sqlight.Error) {
  use _ <- result.try(sqlight.exec("BEGIN IMMEDIATE TRANSACTION;", db))

  case cb(db) {
    Ok(result) -> {
      use _ <- result.try(sqlight.exec("COMMIT TRANSACTION;", db))
      Ok(result)
    }
    Error(error) -> {
      let assert Ok(_) = sqlight.exec("ROLLBACK TRANSACTION;", db)
      Error(error)
    }
  }
}

fn handle_write(
  state: State,
  events: List(Event),
  recv: process.Subject(List(Event)),
) -> actor.Next(State, Message) {
  let result_set = {
    use db <- with_transaction(state.db)

    let decoder = {
      use time <- decode.field(0, decode.int)
      use data <- decode.field(1, decode.string)
      decode.success(Event(time:, data:))
    }

    let latest_sql =
      "
      SELECT time, data FROM events ORDER BY time DESC LIMIT 1;
    "

    use list <- result.try(sqlight.query(
      latest_sql,
      on: db,
      with: [],
      expecting: decoder,
    ))

    let latest_event =
      list.first(list)
      |> result.map(fn(event) { event.time })
      |> result.unwrap(0)
    let events_to_insert =
      list.filter(events, fn(event) { event.time > latest_event })

    let insertion_sql =
      "
      INSERT INTO events (time, data) VALUES (?,?);
      "

    let inserts =
      list.try_map(events_to_insert, fn(event) {
        sqlight.query(
          insertion_sql,
          on: db,
          with: [sqlight.int(event.time), sqlight.text(event.data)],
          expecting: decode.dynamic,
        )
      })

    use _ <- result.try(inserts)

    Ok(events_to_insert)
  }

  case result_set {
    Error(_) -> panic as "could not insert events into db"
    Ok(events) -> {
      process.send(recv, events)
      actor.continue(state)
    }
  }
}

pub fn start(datafile: String) -> Result(EventStore, Nil) {
  let start_result =
    actor.new_with_initialiser(1000, initialize(_, datafile))
    |> actor.on_message(handle_message)
    |> actor.start

  case start_result {
    Ok(start_result) -> {
      process.link(start_result.pid)
      Ok(start_result.data)
    }
    Error(error) -> {
      echo error
      Error(Nil)
    }
  }
}

pub fn close(store: EventStore) {
  let assert Ok(pid) = process.subject_owner(store.subject)
  process.unlink(pid)

  process.send(store.subject, Close)
}

pub fn get_latest(store: EventStore) {
  process.call(store.subject, 1000, GetLatest)
}

pub fn get_from(store: EventStore, from: Int) {
  process.call(store.subject, 1000, GetFrom(from, _))
}

pub fn write(store: EventStore, events: List(Event)) {
  process.call(store.subject, 1000, Write(events, _))
}
