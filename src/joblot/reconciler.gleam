import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervision
import gleam/set
import gleam/time/duration
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

  let time_to_next_reconcile = time_to_next_reconcile(state.last_reconciled)
  process.send_after(state.self, time_to_next_reconcile, Reconcile)

  let current_time = timestamp.system_time()
  actor.continue(State(..state, last_reconciled: current_time))
}

fn time_to_next_reconcile(last_reconciled: timestamp.Timestamp) -> Int {
  let time_since_last_reconciled =
    timestamp.difference(timestamp.system_time(), last_reconciled)
  let time_to_next_reconcile =
    duration.difference(
      duration.milliseconds(heartbeat_interval),
      time_since_last_reconciled,
    )

  let #(seconds, nanoseconds) =
    duration.to_seconds_and_nanoseconds(time_to_next_reconcile)

  let milliseconds = seconds * 1000 + nanoseconds / 1_000_000

  milliseconds
}
