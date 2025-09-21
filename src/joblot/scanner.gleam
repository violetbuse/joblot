import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/set
import gleam/time/timestamp
import joblot/instance
import joblot/sql
import joblot/target.{type Message as TargetMessage}
import pog

const scan_min_interval = 30_000

const scan_timeout = 60_000

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
  let recv_result = process.new_subject()

  let pid =
    process.spawn(fn() {
      let recv_one_off_jobs = scan_one_off_jobs(state.db)
      let recv_cron_jobs = scan_cron_jobs(state.db)

      let selector =
        process.new_selector()
        |> process.select(recv_one_off_jobs)
        |> process.select(recv_cron_jobs)

      let result_1 = process.selector_receive_forever(selector)
      let result_2 = process.selector_receive_forever(selector)

      list.append(result_1, result_2)
      |> set.from_list
      |> process.send(recv_result, _)
    })

  let resulting_set =
    process.receive(recv_result, scan_timeout)
    |> result.map_error(fn(_) {
      process.unlink(pid)
      process.kill(pid)
      panic as "Jobs scan timed out"
    })
    |> result.unwrap(set.new())

  let target_jobs = target.list_jobs(state.target)
  let to_add_to_target = set.difference(resulting_set, target_jobs)
  let to_remove_from_target = set.difference(target_jobs, resulting_set)

  set.each(to_add_to_target, fn(job_id) { target.add_job(state.target, job_id) })

  set.each(to_remove_from_target, fn(job_id) {
    target.remove_job(state.target, job_id)
  })

  let time_to_next_scan = time_to_next_scan(state.last_scanned)
  process.send_after(state.self, time_to_next_scan, Scan)

  let current_time = timestamp.system_time()
  actor.continue(State(..state, last_scanned: current_time))
}

fn scan_one_off_jobs(
  db: process.Name(pog.Message),
) -> process.Subject(List(instance.JobId)) {
  let response_subject = process.new_subject()

  process.spawn(fn() {
    let result = scan_one_off_jobs_loop(db, "")
    process.send(response_subject, result)
  })

  response_subject
}

fn scan_one_off_jobs_loop(
  db: process.Name(pog.Message),
  cursor: String,
) -> List(instance.JobId) {
  let #(current_time, _) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  let ten_minutes_from_now = current_time + 10 * 60

  let connection = pog.named_connection(db)

  case sql.scan_one_off_jobs(connection, ten_minutes_from_now, cursor, 100) {
    Error(_) -> panic as "Failed to scan one off jobs"
    Ok(pog.Returned(0, _)) -> []
    Ok(pog.Returned(_, rows)) -> {
      let job_ids = list.map(rows, fn(row) { instance.OneTime(row.id) })

      let new_cursor =
        list.last(rows)
        |> result.map(fn(row) { row.id })
        |> result.unwrap("")

      list.append(job_ids, scan_one_off_jobs_loop(db, new_cursor))
    }
  }
}

fn scan_cron_jobs(
  db: process.Name(pog.Message),
) -> process.Subject(List(instance.JobId)) {
  let response_subject = process.new_subject()

  process.spawn(fn() {
    let result = scan_cron_jobs_loop(db, "")
    process.send(response_subject, result)
  })

  response_subject
}

fn scan_cron_jobs_loop(
  db: process.Name(pog.Message),
  cursor: String,
) -> List(instance.JobId) {
  let connection = pog.named_connection(db)

  case sql.scan_cron(connection, cursor, 100) {
    Error(_) -> panic as "Failed to scan cron jobs"
    Ok(pog.Returned(0, _)) -> []
    Ok(pog.Returned(_, rows)) -> {
      let job_ids = list.map(rows, fn(row) { instance.Cron(row.id) })

      let new_cursor =
        list.last(rows)
        |> result.map(fn(row) { row.id })
        |> result.unwrap("")

      list.append(job_ids, scan_cron_jobs_loop(db, new_cursor))
    }
  }
}

fn time_to_next_scan(last_scanned: timestamp.Timestamp) -> Int {
  let last_scanned = timestamp.to_unix_seconds_and_nanoseconds(last_scanned)
  let last_scanned_in_milliseconds =
    last_scanned.0 * 1000 + last_scanned.1 / 1_000_000

  let current_time =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time())
  let current_time_in_milliseconds =
    current_time.0 * 1000 + current_time.1 / 1_000_000

  let earliest_next_scan = last_scanned_in_milliseconds + scan_min_interval
  let target_next_scan = current_time_in_milliseconds + 100
  let time_to_next_scan =
    int.max(earliest_next_scan, target_next_scan) - current_time_in_milliseconds

  time_to_next_scan
}
