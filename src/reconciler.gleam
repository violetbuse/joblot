import gleam/otp/actor
import gleam/erlang/process
import target.{type Message as TargetMessage}
import registry.{type Message as RegistryMessage}
import gleam/otp/supervision

pub fn start_reconciler(
    name: process.Name(Message), 
    target target: process.Name(TargetMessage), 
    registry registry: process.Name(RegistryMessage)
) {
    actor.new_with_initialiser(5000, fn (subject) {

        let target_subject = process.named_subject(target)
        let registry_subject = process.named_subject(registry)

        let initialised = actor.initialised(State(target_subject, registry_subject))
        |> actor.returning(subject)
        Ok(initialised)
    })
    |> actor.on_message(handle_message)
    |> actor.named(name)
    |> actor.start
}

pub fn supervised(
    name: process.Name(Message), 
    target target: process.Name(TargetMessage), 
    registry registry: process.Name(RegistryMessage)
) {
    supervision.worker(fn () {
        start_reconciler(name, target, registry)
    })
}

pub opaque type Message {}

type State {
    State(target: process.Subject(TargetMessage), registry: process.Subject(RegistryMessage))
}

fn handle_message(state: State, _message: Message) -> actor.Next(State, Message) {
    actor.continue(state)
}