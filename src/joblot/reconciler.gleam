import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/otp/actor
import gleam/otp/supervision
import gleam/set
import gleam/time/timestamp
import joblot/registry.{type Message as RegistryMessage}
import joblot/target.{type Message as TargetMessage}

const heartbeat_interval = 10_000

pub fn start_reconciler(
  target target: process.Name(TargetMessage),
  registry registry: process.Name(RegistryMessage),
) {
  actor.new_with_initialiser(5000, fn(subject) {
    process.send(subject, Reconcile)

    let initialised =
      actor.initialised(State(
        subject,
        target,
        registry,
        timestamp.system_time(),
      ))
      |> actor.returning(subject)
    Ok(initialised)
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

pub fn supervised(
  target target: process.Name(TargetMessage),
  registry registry: process.Name(RegistryMessage),
) {
  supervision.worker(fn() { start_reconciler(target, registry) })
}

pub opaque type Message {
  Reconcile
}

type State {
  State(
    self: process.Subject(Message),
    target: process.Name(TargetMessage),
    registry: process.Name(RegistryMessage),
    last_reconciled: timestamp.Timestamp,
  )
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Reconcile -> reconcile(state)
  }
}

fn reconcile(state: State) -> actor.Next(State, Message) {
  let target_jobs = target.list_jobs(state.target)
  let registry_jobs = registry.list_instances(state.registry)

  let in_target_not_in_registry = set.difference(target_jobs, registry_jobs)
  let in_registry_not_in_target = set.difference(registry_jobs, target_jobs)

  set.each(in_target_not_in_registry, fn(job_id) {
    registry.add_instance(state.registry, job_id)
  })

  set.each(in_registry_not_in_target, fn(job_id) {
    registry.remove_instance(state.registry, job_id)
  })

  process.sleep(995)
  let time_to_next_reconcile = time_to_next_reconcile(state.last_reconciled)
  process.send_after(state.self, time_to_next_reconcile, Reconcile)

  let current_time = timestamp.system_time()
  actor.continue(State(..state, last_reconciled: current_time))
}

fn time_to_next_reconcile(last_reconciled: timestamp.Timestamp) -> Int {
  let last_reconciled =
    timestamp.to_unix_seconds_and_nanoseconds(last_reconciled)
  let last_reconciled_in_milliseconds =
    last_reconciled.0 * 1000 + last_reconciled.1 / 1_000_000

  let current_time =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp.system_time())
  let current_time_in_milliseconds =
    current_time.0 * 1000 + current_time.1 / 1_000_000

  let earliest_next_reconcile =
    last_reconciled_in_milliseconds + heartbeat_interval
  let target_next_reconcile = current_time_in_milliseconds + 100

  let time_to_next_reconcile =
    int.max(earliest_next_reconcile, target_next_reconcile)
    - current_time_in_milliseconds

  time_to_next_reconcile
}
