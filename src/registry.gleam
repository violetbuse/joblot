import gleam/otp/actor
import gleam/erlang/process
import gleam/dict.{type Dict}
// import instance.{type JobId, type Message as InstanceMessage}
import gleam/otp/supervision
import gleam/result

pub fn start_registry(name: process.Name(Message)) {
    actor.new_with_initialiser(5000, fn (subject) {
        let initialization = {
            Ok(State(subject, dict.new()))
        }

        use state <- result.try(initialization)

        let selector = process.new_selector()
        |> process.select(subject)
        |> process.select_trapped_exits(fn (message) {
            let process.ExitMessage(pid, reason) = message
            InstanceExited(pid, reason)
        })

        actor.initialised(state)
        |> actor.selecting(selector)
        |> actor.returning(subject)
        |> Ok
    })
    |> actor.on_message(handle_message)
    |> actor.named(name)
    |> actor.start
}

pub fn supervised(name: process.Name(Message)) {
    supervision.worker(fn () {
        start_registry(name)
    })
}

type InstanceInfo {}

type State {
    State(self: process.Subject(Message), instances: Dict(process.Pid, InstanceInfo))
}

pub opaque type Message {
    InstanceExited(process.Pid, reason: process.ExitReason)
}

fn handle_message(state: State, _message: Message) -> actor.Next(State, Message) {
    actor.continue(state)
}
