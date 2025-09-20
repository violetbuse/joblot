import gleam/otp/actor

pub type JobId {
    Recurring(String)
    OneTime(String)
    RateLimited(String)
}

pub fn start_instance(job_id: JobId) {
    actor.new_with_initialiser(5000, fn (subject) {
        let initialised = actor.initialised(State(job_id))
        |> actor.returning(subject)

        Ok(initialised)
    })
    |> actor.on_message(handle_message)
    |> actor.start
}

type State {
    State(job_id: JobId)
}

pub type Message {

}

fn handle_message (state: State, _message: Message) -> actor.Next(State, Message) {
    actor.continue(state)
}
