import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import joblot/lock
import pog

pub type JobId {
  Cron(String)
  OneTime(String)
}

fn job_id_to_string(job_id: JobId) -> String {
  case job_id {
    Cron(id) -> "cron_" <> id
    OneTime(id) -> "one_time_" <> id
  }
}

pub fn start(job_id: JobId, db: process.Name(pog.Message)) {
  let started =
    actor.new_with_initialiser(500, fn(subject) {
      let selector =
        process.new_selector()
        |> process.select(subject)
        |> process.select_monitors(fn(down) {
          let assert process.ProcessDown(_, pid, reason) = down
          LockExited(pid, reason)
        })

      actor.initialised(State(job_id, db, None))
      |> actor.selecting(selector)
      |> actor.returning(subject)
      |> Ok
    })
    |> actor.on_message(handle_message)
    |> actor.start

  let _ =
    started
    |> result.map(fn(started) { process.send(started.data, Initialize) })

  started
}

type State {
  State(job_id: JobId, db: process.Name(pog.Message), lock: Option(lock.Lock))
}

pub type Message {
  Initialize
  LockExited(process.Pid, reason: process.ExitReason)
  Exit
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case state {
    State(job_id, db, None) ->
      case message {
        Initialize -> initialize(job_id, db)
        _ -> actor.stop_abnormal("Invalid message")
      }
    State(_, _, Some(lock)) ->
      case message {
        LockExited(pid, reason) -> handle_lock_exited(state, pid, reason)
        Initialize -> actor.continue(state)
        Exit -> {
          lock.exit_lock(lock)
          actor.stop()
        }
      }
  }
}

fn initialize(
  job_id: JobId,
  db: process.Name(pog.Message),
) -> actor.Next(State, Message) {
  let state_result = {
    use lock <- result.try(
      lock.start_lock(job_id_to_string(job_id), db)
      |> result.replace_error("Failed to start lock"),
    )

    lock.monitor_lock(lock)

    Ok(State(job_id, db, Some(lock)))
  }

  case state_result {
    Ok(state) -> actor.continue(state)
    Error(reason) -> {
      actor.stop_abnormal(reason)
    }
  }
}

fn handle_lock_exited(
  data: State,
  pid: process.Pid,
  reason: process.ExitReason,
) -> actor.Next(State, Message) {
  case reason {
    process.Normal | process.Killed -> actor.stop()
    _ -> {
      let restart_result =
        lock.restart_lock(
          data.lock,
          pid,
          job_id_to_string(data.job_id),
          data.db,
        )

      case restart_result {
        Ok(lock) -> {
          actor.continue(State(..data, lock: Some(lock)))
        }
        Error(_) -> {
          actor.stop_abnormal("Failed to restart lock")
        }
      }
    }
  }
}

pub fn stop(subject: process.Subject(Message)) {
  process.send(subject, Exit)
}
