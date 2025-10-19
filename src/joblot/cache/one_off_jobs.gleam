import gleam/bool
import gleam/erlang/process
import gleam/http
import gleam/list
import gleam/otp/supervision
import gleam/result
import gleam/string
import gleam/uri
import joblot/cache/attempts
import joblot/cache/builder
import joblot/cache/registry
import joblot/cache/sql
import joblot/pubsub
import pog

pub type Message =
  registry.Message(Job)

pub type Attempt =
  attempts.Attempt

pub fn is_successful(attempt: Attempt) -> Bool {
  attempts.is_successful(attempt)
}

pub type Job {
  Job(
    id: String,
    created_at: Int,
    user_id: String,
    tenant_id: String,
    metadata: String,
    method: http.Method,
    url: uri.Uri,
    headers: List(#(String, String)),
    body: String,
    execute_at: Int,
    maximum_attempts: Int,
    initial_delay_secs: Int,
    retry_factor: Float,
    maximum_delay_secs: Int,
    non_2xx_is_failure: Bool,
    timeout_ms: Int,
    completed: Bool,
    attempts: List(attempts.Attempt),
  )
}

fn get_data(id: String, ctx: builder.Context) -> Result(Job, String) {
  let connection = pog.named_connection(ctx.db)
  use pog.Returned(count, rows) <- result.try(
    sql.get_one_off_job(connection, id)
    |> result.replace_error("Coult not fetch job from db. id: " <> id),
  )

  use <- bool.guard(
    when: count != 1,
    return: Error("Job does not exist, id: " <> id),
  )

  let assert [row] = rows

  use attempts <- result.try(attempts.get_attempts(
    ctx.db,
    row.execute_at,
    id,
    20_000,
  ))

  use method <- result.try(
    http.parse_method(row.method)
    |> result.replace_error(
      "Invalid http method: " <> row.method <> " job_id: " <> id,
    ),
  )

  use url <- result.try(
    uri.parse(row.url)
    |> result.replace_error("Invalid url: " <> row.url <> " job_id: " <> id),
  )

  let headers =
    row.headers
    |> list.map(string.split_once(_, ":"))
    |> result.all

  use headers <- result.try(
    headers |> result.replace_error("Invalid headers, job_id: " <> id),
  )

  Ok(Job(
    id: row.id,
    created_at: row.created_at,
    user_id: row.user_id,
    tenant_id: row.tenant_id,
    metadata: row.metadata,
    method: method,
    url: url,
    headers: headers,
    body: row.body,
    execute_at: row.execute_at,
    maximum_attempts: row.maximum_attempts,
    initial_delay_secs: row.initial_retry_delay_seconds,
    retry_factor: row.retry_delay_factor,
    maximum_delay_secs: row.maximum_retry_delay_seconds,
    non_2xx_is_failure: row.non_2xx_is_failure,
    timeout_ms: row.timeout_ms,
    completed: row.completed,
    attempts: attempts,
  ))
}

pub fn start_cache(
  name: process.Name(registry.Message(Job)),
  db: process.Name(pog.Message),
  pubsub: process.Name(pubsub.Message),
) {
  registry.new()
  |> registry.name(name)
  |> registry.pubsub_category("one_off_jobs")
  |> registry.get_data(get_data)
  |> registry.heartbeat_ms(3 * 60 * 1000)
  |> registry.start(db, pubsub)
}

pub fn supervised(
  name: process.Name(registry.Message(Job)),
  db: process.Name(pog.Message),
  pubsub: process.Name(pubsub.Message),
) {
  supervision.worker(fn() { start_cache(name, db, pubsub) })
}
