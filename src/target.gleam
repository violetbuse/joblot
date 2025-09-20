import gleam/result
import instance.{type JobId}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/erlang/process

pub fn start_target(name: process.Name(Message)) {
    actor.new_with_initialiser(5000, fn (subject) {
        let initialization = {
            process.send(subject, UpdateTarget)
            Ok(State(subject, []))
        }

        use state <- result.try(initialization)

        actor.initialised(state)
        |> actor.returning(subject)
        |> Ok
    })
    |> actor.on_message(handle_message)
    |> actor.named(name)
    |> actor.start
}

pub fn supervised(name: process.Name(Message)) {
    supervision.worker(fn () {
        start_target(name)
    })
}

pub opaque type Message {
    UpdateTarget
}

type State {
    State(self: process.Subject(Message), job_ids: List(JobId))
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
    case message {
        UpdateTarget -> update_target(state)
    }
}

fn update_target(state: State) -> actor.Next(State, Message) {
    let State(self, _) = state
    /// actually update the target
    process.send_after(self, 5000, UpdateTarget)
    actor.continue(state)
}
