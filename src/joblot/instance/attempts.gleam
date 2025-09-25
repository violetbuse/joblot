import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import joblot/instance/sql
import joblot/utils
import pog

pub type Response {
  Response(
    status_code: Int,
    headers: List(String),
    body: String,
    response_time_ms: Int,
  )
}

pub type Attempt {
  SuccessfulRequest(attempted_at: Int, response: Response)
  FailedRequest(attempted_at: Int, response: Response)
  RequestError(attempted_at: Int, error: String)
}

pub fn get_attempts_for_planned_at(
  db: process.Name(pog.Message),
  job_id: String,
  planned_at: Int,
) -> Result(List(Attempt), pog.QueryError) {
  let connection = pog.named_connection(db)
  use pog.Returned(_, error_rows) <- result.try(sql.list_errored_attempts(
    connection,
    planned_at,
    job_id,
  ))
  use pog.Returned(_, response_rows) <- result.try(sql.list_responses(
    connection,
    planned_at,
    job_id,
  ))

  let error_attempts = {
    use item <- list.map(error_rows)
    RequestError(item.attempted_at, item.error)
  }
  let response_attempts = {
    use item <- list.map(response_rows)
    let response =
      Response(
        item.res_status_code,
        item.res_headers,
        item.res_body,
        item.response_time_ms,
      )
    case item.success {
      True -> SuccessfulRequest(item.attempted_at, response)
      False -> FailedRequest(item.attempted_at, response)
    }
  }

  let attempts =
    list.append(error_attempts, response_attempts)
    |> list.sort(fn(a, b) { int.compare(a.attempted_at, b.attempted_at) })

  Ok(attempts)
}

pub fn is_successful(attempt: Attempt) -> Bool {
  case attempt {
    SuccessfulRequest(..) -> True
    FailedRequest(..) -> False
    RequestError(..) -> False
  }
}

pub type ShouldRetry {
  IsAlreadySuccessful
  MaximumAttemptsReached
  CanRetry
}

pub fn should_retry(
  attempts: List(Attempt),
  maximum_attempts: Int,
) -> ShouldRetry {
  let hit_maximum_attempts = attempts |> list.length >= maximum_attempts
  use <- bool.guard(hit_maximum_attempts, return: MaximumAttemptsReached)
  let has_successful_attempt = attempts |> list.any(is_successful)
  use <- bool.guard(has_successful_attempt, return: IsAlreadySuccessful)
  CanRetry
}

/// delay in seconds
/// factor is the factor by which the delay is multiplied
/// maximum is the maximum delay in seconds
pub fn next_retry_time(
  attempts: List(Attempt),
  planned_at: Int,
  initial delay: Int,
  factor factor: Float,
  maximum maximum: Int,
) -> Int {
  let attempt_count = attempts |> list.length
  let now = utils.get_unix_timestamp()
  let last_attempt_time =
    attempts
    |> list.last
    |> result.map(fn(attempt) { attempt.attempted_at })
    |> result.unwrap(now)

  use <- bool.guard(attempt_count == 0, return: planned_at)
  let assert Ok(multiplicand) =
    float.power(factor, attempt_count |> int.to_float)
  let raw_delay = { delay |> int.to_float } *. multiplicand
  let delay = int.clamp(float.round(raw_delay), delay, maximum)

  last_attempt_time + delay
}
