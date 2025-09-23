import glanoid
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/time/timestamp
import joblot/lock/sql
import pog

const heartbeat_interval_ms = 14_000

const lock_expiration_ms = 30_000

pub opaque type Lock {
  Lock(pid: process.Pid, subject: process.Subject(Message))
}

pub fn start_lock(
  id: String,
  db: process.Name(pog.Message),
  manager: process.Name(LockMgrMessage),
) {
  actor.new_with_initialiser(5000, fn(subject) {
    process.send_after(subject, heartbeat_interval_ms, Heartbeat)

    let assert Ok(nanoid) = glanoid.make_generator(glanoid.default_alphabet)
    let nonce = nanoid(21)

    let initial_state =
      State(subject, db, manager, id, nonce, False)
      |> try_acquire_lock

    let initialised =
      actor.initialised(initial_state)
      |> actor.returning(subject)
    Ok(initialised)
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

pub fn supervised(
  id: String,
  name: process.Name(LockMgrMessage),
  db: process.Name(pog.Message),
) {
  supervision.worker(fn() { start_lock(id, db, name) })
}

type State {
  State(
    self: process.Subject(Message),
    db: process.Name(pog.Message),
    manager: process.Name(LockMgrMessage),
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
      process.send_after(state.self, heartbeat_interval_ms, Heartbeat)
      let manager_subject = process.named_subject(state.manager)
      let self_lock = Lock(process.self(), state.self)

      case
        try_acquire_lock(state),
        process.call(manager_subject, 1000, RegisterLock(
          _,
          state.id,
          state.nonce,
          self_lock,
        ))
      {
        _, Error(_) ->
          actor.stop_abnormal("Failed to register lock with manager")
        new_state, Ok(_) -> actor.continue(new_state)
      }
    }
    Exit -> {
      let _ =
        sql.release_lock(pog.named_connection(state.db), state.id, state.nonce)

      let manager_subject = process.named_subject(state.manager)
      process.send(manager_subject, DeregisterLock(state.id, state.nonce))

      actor.stop()
    }
  }
}

fn try_acquire_lock(state: State) -> State {
  let connection = pog.named_connection(state.db)

  let State(_, _, _, id, nonce, _) = state

  let acquisition_result = {
    let #(current_time, _) =
      timestamp.system_time()
      |> timestamp.to_unix_seconds_and_nanoseconds

    let expires_at = current_time + lock_expiration_ms / 1000

    case sql.insert_lock(connection, id, nonce, expires_at) {
      Ok(pog.Returned(1, _)) -> {
        Ok(Nil)
      }
      _failure_1 -> {
        case sql.update_lock(connection, id, nonce, expires_at) {
          Ok(pog.Returned(1, _)) -> {
            Ok(Nil)
          }
          _failure_2 -> {
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

pub fn start_lock_manager(
  name: process.Name(LockMgrMessage),
  db: process.Name(pog.Message),
) {
  let start_result =
    actor.new_with_initialiser(1000, fn(self) {
      process.send_after(self, heartbeat_interval_ms / 3, LockMgrHeartbeat)

      actor.initialised(LockMgrState(self, db, dict.new()))
      |> actor.returning(self)
      |> Ok
    })
    |> actor.on_message(handle_lock_mgr_message)
    |> actor.named(name)
    |> actor.start

  start_result
}

pub fn lock_manager_supervised(
  name: process.Name(LockMgrMessage),
  db: process.Name(pog.Message),
) {
  supervision.worker(fn() { start_lock_manager(name, db) })
}

pub opaque type LockMgrMessage {
  LockMgrHeartbeat
  RegisterLock(
    response_to: process.Subject(Result(Nil, Nil)),
    id: String,
    nonce: String,
    lock: Lock,
  )
  DeregisterLock(id: String, nonce: String)
  GetLock(id: String, reply_to: process.Subject(Option(Lock)))
}

type LockMgrState {
  LockMgrState(
    self: process.Subject(LockMgrMessage),
    db: process.Name(pog.Message),
    locks: dict.Dict(String, #(String, Lock)),
  )
}

fn handle_lock_mgr_message(
  state: LockMgrState,
  message: LockMgrMessage,
) -> actor.Next(LockMgrState, LockMgrMessage) {
  case message {
    LockMgrHeartbeat -> {
      process.send_after(
        state.self,
        heartbeat_interval_ms / 3,
        LockMgrHeartbeat,
      )

      let #(current_time, _) =
        timestamp.system_time()
        |> timestamp.to_unix_seconds_and_nanoseconds

      case sql.clear_locks(pog.named_connection(state.db), current_time) {
        Ok(_) -> actor.continue(state)
        Error(_) -> actor.stop_abnormal("Failed to clear locks")
      }
    }
    RegisterLock(response_to, id, nonce, lock) -> {
      let new_locks =
        dict.upsert(state.locks, id, fn(existing_option) {
          let should_replace = case existing_option {
            None -> True
            Some(#(existing_nonce, existing_lock)) -> {
              case nonce == existing_nonce {
                True -> True
                False -> !process.is_alive(existing_lock.pid)
              }
            }
          }

          let _ = case should_replace {
            True -> process.send(response_to, Ok(Nil))
            False -> process.send(response_to, Error(Nil))
          }

          case existing_option, should_replace {
            None, _ -> #(nonce, lock)
            _, True -> #(nonce, lock)
            Some(prev), _ -> prev
          }
        })
      actor.continue(LockMgrState(..state, locks: new_locks))
    }
    DeregisterLock(id, nonce) -> {
      let new_locks =
        dict.filter(state.locks, fn(k, v) {
          case k, v {
            k, #(n, _) if k == id && n == nonce -> False
            _, _ -> True
          }
        })

      actor.continue(LockMgrState(..state, locks: new_locks))
    }
    GetLock(id, reply_to) -> {
      case dict.get(state.locks, id) {
        Error(_) -> {
          process.send(reply_to, None)
        }
        Ok(#(_, lock)) -> {
          process.send(reply_to, Some(lock))
        }
      }

      actor.continue(state)
    }
  }
}

pub fn has_lock(manager: process.Name(LockMgrMessage), id: String) -> Bool {
  let result = {
    use lock <- option.map(
      process.call(process.named_subject(manager), 1000, GetLock(id, _)),
    )
    is_locked(lock)
  }

  case result {
    Some(locked) -> locked
    None -> False
  }
}
