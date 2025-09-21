import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervision
import joblot/registry.{type Message as RegistryMessage}
import joblot/target.{type Message as TargetMessage}

const heartbeat_interval = 10_000

pub fn start_reconciler(
  target target: process.Name(TargetMessage),
  registry registry: process.Name(RegistryMessage),
) {
  actor.new_with_initialiser(5000, fn(subject) {
    process.send(subject, Heartbeat)

    let target_subject = process.named_subject(target)
    let registry_subject = process.named_subject(registry)

    let initialised =
      actor.initialised(State(target_subject, registry_subject))
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
  Heartbeat
}

type State {
  State(
    target: process.Subject(TargetMessage),
    registry: process.Subject(RegistryMessage),
  )
}

fn handle_message(state: State, _message: Message) -> actor.Next(State, Message) {
  actor.continue(state)
}
