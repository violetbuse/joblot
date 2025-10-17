import gleam/erlang/process
import gleam/otp/supervision
import joblot/cache/builder
import joblot/cache/registry
import pog

pub type Job {
  Job
}

fn get_data(id: String, ctx: builder.Context) -> Result(Job, String) {
  todo
}

pub fn start_cache(
  name: process.Name(registry.Message(Job)),
  db: process.Name(pog.Message),
) {
  registry.new()
  |> registry.name(name)
  |> registry.pubsub_category("one_off_jobs")
  |> registry.get_data(get_data)
  |> registry.heartbeat_ms(3 * 60 * 1000)
  |> registry.start(db)
}

pub fn supervised(
  name: process.Name(registry.Message(Job)),
  db: process.Name(pog.Message),
) {
  supervision.worker(fn() { start_cache(name, db) })
}
