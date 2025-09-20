import gleam/erlang/process
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

      actor.initialised(Uninitialized(job_id, db))
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
  Uninitialized(job_id: JobId, db: process.Name(pog.Message))
  Initialized(job_id: JobId, lock: lock.Lock, db: process.Name(pog.Message))
}

fn initialized_to_data(state: State) -> InitializedState {
  let assert Initialized(job_id, lock, db) = state
  Data(job_id, lock, db)
}

type InitializedState {
  Data(job_id: JobId, lock: lock.Lock, db: process.Name(pog.Message))
}

fn data_to_initialized(state: InitializedState) -> State {
  Initialized(state.job_id, state.lock, state.db)
}

pub type Message {
  Initialize
  LockExited(process.Pid, reason: process.ExitReason)
  Exit
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case state {
    Uninitialized(job_id, db) ->
      case message {
        Initialize -> initialize(job_id, db)
        _ -> actor.stop_abnormal("Invalid message")
      }
    Initialized(_, lock, _) ->
      case message {
        LockExited(pid, reason) ->
          handle_lock_exited(initialized_to_data(state), pid, reason)
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

    let data = Data(job_id, lock, db)

    Ok(data_to_initialized(data))
  }

  case state_result {
    Ok(state) -> actor.continue(state)
    Error(reason) -> {
      actor.stop_abnormal(reason)
    }
  }
}

fn handle_lock_exited(
  data: InitializedState,
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
          actor.continue(data_to_initialized(Data(..data, lock: lock)))
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
