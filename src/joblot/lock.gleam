import glanoid
import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/time/timestamp
import joblot/sql
import pog

const heartbeat_interval = 14_000

const lock_expiration = 30_000

pub opaque type Lock {
  Lock(pid: process.Pid, subject: process.Subject(Message))
}

pub fn start_lock(id: String, db: process.Name(pog.Message)) {
  let start_result =
    actor.new_with_initialiser(5000, fn(subject) {
      process.send_after(subject, heartbeat_interval, Heartbeat)

      let assert Ok(nanoid) = glanoid.make_generator(glanoid.default_alphabet)
      let nonce = nanoid(21)

      let initial_state =
        State(subject, db, id, nonce, False)
        |> try_acquire_lock

      let initialised =
        actor.initialised(initial_state)
        |> actor.returning(subject)
      Ok(initialised)
    })
    |> actor.on_message(handle_message)
    |> actor.start

  use started <- result.try(start_result)
  Ok(Lock(started.pid, started.data))
}

pub fn monitor_lock(lock: Lock) {
  process.monitor(lock.pid)
}

pub fn restart_lock(
  lock: Option(Lock),
  exited_pid: process.Pid,
  id: String,
  db: process.Name(pog.Message),
) -> Result(Lock, actor.StartError) {
  let restart_lock = fn() {
    use new_lock <- result.try(start_lock(id, db))
    monitor_lock(new_lock)
    Ok(new_lock)
  }

  case lock {
    None -> {
      restart_lock()
    }
    Some(lock) if lock.pid == exited_pid -> {
      process.send(lock.subject, Exit)
      restart_lock()
    }
    Some(lock) -> {
      Ok(lock)
    }
  }
}

type State {
  State(
    self: process.Subject(Message),
    db: process.Name(pog.Message),
    id: String,
    nonce: String,
    acquired: Bool,
  )
}

pub opaque type Message {
  Heartbeat
  QueryLock(reply_to: process.Subject(Bool))
  Exit
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    QueryLock(reply_to) -> {
      process.send(reply_to, state.acquired)
      actor.continue(state)
    }
    Heartbeat -> {
      process.send_after(state.self, heartbeat_interval, Heartbeat)

      try_acquire_lock(state)
      |> actor.continue
    }
    Exit -> {
      let _ =
        sql.release_lock(pog.named_connection(state.db), state.id, state.nonce)
      actor.stop()
    }
  }
}

fn try_acquire_lock(state: State) -> State {
  let connection = pog.named_connection(state.db)

  let State(_, _, id, nonce, _) = state

  let acquisition_result = {
    let #(current_time, _) =
      timestamp.system_time()
      |> timestamp.to_unix_seconds_and_nanoseconds

    let expires_at = current_time + lock_expiration

    case sql.insert_lock(connection, id, nonce, expires_at) {
      Ok(pog.Returned(1, _)) -> {
        Ok(Nil)
      }
      _ -> {
        case sql.update_lock(connection, id, nonce, expires_at) {
          Ok(pog.Returned(1, _)) -> {
            Ok(Nil)
          }
          _ -> {
            Error(Nil)
          }
        }
      }
    }
  }

  let acquired = case acquisition_result {
    Error(_) -> False
    Ok(_) -> {
      case sql.query_lock(connection, id) {
        Ok(pog.Returned(_, [sql.QueryLockRow(_, locked_nonce, expires_at)])) -> {
          let #(current_time, _) =
            timestamp.system_time()
            |> timestamp.to_unix_seconds_and_nanoseconds

          let locked = current_time < expires_at && locked_nonce == nonce

          locked
        }
        _ -> False
      }
    }
  }

  State(..state, acquired: acquired)
}

pub fn is_locked(lock: Lock) -> Bool {
  actor.call(lock.subject, 1000, QueryLock)
}

pub fn exit_lock(lock: Lock) {
  process.send(lock.subject, Exit)
}
