import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervision
import gleam/time/duration
import gleam/time/timestamp
import joblot/target.{type Message as TargetMessage}
import pog

const scan_min_interval = 30_000

pub fn start_scanner(
  db: process.Name(pog.Message),
  target: process.Name(TargetMessage),
) {
  actor.new_with_initialiser(5000, fn(subject) {
    process.send(subject, Scan)

    let initialised =
      actor.initialised(State(subject, db, target, timestamp.system_time()))
      |> actor.returning(subject)
    Ok(initialised)
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

pub fn supervised(
  db: process.Name(pog.Message),
  target: process.Name(TargetMessage),
) {
  supervision.worker(fn() { start_scanner(db, target) })
}

pub opaque type Message {
  Scan
}

type State {
  State(
    self: process.Subject(Message),
    db: process.Name(pog.Message),
    target: process.Name(TargetMessage),
    last_scanned: timestamp.Timestamp,
  )
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Scan -> scan(state)
  }
}

fn scan(state: State) -> actor.Next(State, Message) {
  let time_to_next_scan = time_to_next_scan(state.last_scanned)
  process.send_after(state.self, time_to_next_scan, Scan)

  todo
  "actually scan and put into target"

  let current_time = timestamp.system_time()
  actor.continue(State(..state, last_scanned: current_time))
}

fn time_to_next_scan(last_scanned: timestamp.Timestamp) -> Int {
  let time_since_last_scanned =
    timestamp.difference(timestamp.system_time(), last_scanned)
  let time_to_next_scan =
    duration.difference(
      duration.milliseconds(scan_min_interval),
      time_since_last_scanned,
    )

  let #(seconds, nanoseconds) =
    duration.to_seconds_and_nanoseconds(time_to_next_scan)

  let milliseconds = seconds * 1000 + nanoseconds / 1_000_000

  milliseconds
}
