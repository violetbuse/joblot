import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/set
import joblot/instance.{type JobId}

pub fn start_target(name: process.Name(Message)) {
  actor.new_with_initialiser(5000, fn(subject) {
    let initialization = {
      Ok(State(subject, set.new()))
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
  supervision.worker(fn() { start_target(name) })
}

pub opaque type Message {
  AddJob(JobId)
  RemoveJob(JobId)
  ListJobs(reply_to: process.Subject(List(JobId)))
}

type State {
  State(self: process.Subject(Message), job_ids: set.Set(JobId))
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    AddJob(job_id) -> handle_add_job(state, job_id)
    RemoveJob(job_id) -> handle_remove_job(state, job_id)
    ListJobs(reply_to) -> handle_list_jobs(state, reply_to)
  }
}

fn handle_add_job(state: State, job_id: JobId) -> actor.Next(State, Message) {
  actor.continue(State(..state, job_ids: set.insert(state.job_ids, job_id)))
}

fn handle_remove_job(state: State, job_id: JobId) -> actor.Next(State, Message) {
  actor.continue(State(..state, job_ids: set.delete(state.job_ids, job_id)))
}

fn handle_list_jobs(
  state: State,
  reply_to: process.Subject(List(JobId)),
) -> actor.Next(State, Message) {
  process.send(reply_to, set.to_list(state.job_ids))
  actor.continue(state)
}
