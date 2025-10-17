import glanoid
import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import joblot/executor
import joblot/instance/sql
import pog

pub type JobType {
  OneOffJob
  CronJob
}

pub type Response {
  Response(
    status_code: Int,
    headers: List(String),
    body: String,
    response_time_ms: Int,
  )
}

pub type Attempt {
  SuccessfulRequest(attempted_at: Int, planned_at: Int, response: Response)
  FailedRequest(attempted_at: Int, planned_at: Int, response: Response)
  RequestError(attempted_at: Int, planned_at: Int, error: String)
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
    RequestError(item.attempted_at, item.planned_at, item.error)
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
      True -> SuccessfulRequest(item.attempted_at, item.planned_at, response)
      False -> FailedRequest(item.attempted_at, item.planned_at, response)
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
  let last_attempt_time =
    attempts
    |> list.last
    |> result.map(fn(attempt) { attempt.attempted_at })
    |> result.unwrap(planned_at)

  use <- bool.guard(attempt_count == 0, return: planned_at)
  let assert Ok(multiplicand) =
    float.power(factor, attempt_count |> int.to_float)
  let raw_delay = { delay |> int.to_float } *. multiplicand
  let delay = int.clamp(float.round(raw_delay), delay, maximum)

  last_attempt_time + delay
}

pub type AttemptSaveData {
  AttemptSaveData(
    planned_at: Int,
    attempted_at: Int,
    job_id: String,
    job_type: JobType,
    user_id: String,
    tenant_id: String,
  )
}

pub fn save_response(
  db: process.Name(pog.Message),
  data: AttemptSaveData,
  request: executor.ExecutorRequest,
  result: Result(executor.ExecutorResponse, executor.ExecutorError),
) -> Result(Nil, pog.QueryError) {
  let connection = pog.named_connection(db)
  let save_error = case data.job_type {
    OneOffJob -> sql.insert_error_for_one_off
    CronJob -> sql.insert_error_for_cron
  }
  let save_response = case data.job_type {
    OneOffJob -> sql.insert_response_for_one_off
    CronJob -> sql.insert_response_for_cron
  }

  let assert Ok(nanoid) = glanoid.make_generator(glanoid.default_alphabet)
  let id = "attempt_" <> nanoid(21)

  case result {
    Ok(response) -> {
      let is_2xx_status_code =
        response.status_code >= 200 && response.status_code < 300
      let is_failure =
        is_2xx_status_code == False && request.non_2xx_is_failure == True
      let success = !is_failure

      save_response(
        connection,
        id,
        data.planned_at,
        data.attempted_at,
        data.user_id,
        data.tenant_id,
        data.job_id,
        request.method,
        request.url,
        request.headers,
        request.body,
        response.status_code,
        response.headers,
        response.body,
        response.response_time_ms,
        success,
      )
      |> result.replace(Nil)
    }
    Error(error_type) -> {
      let error_text = case error_type {
        executor.TimeoutError -> "Request timed out"
        executor.PrivateIpError -> "Requests to private IPs are not allowed"
        executor.InvalidUtf8Response -> "Invalid UTF-8 response"
        executor.FailedToConnect -> "Failed to connect"
      }

      save_error(
        connection,
        id,
        data.planned_at,
        data.attempted_at,
        data.user_id,
        data.tenant_id,
        data.job_id,
        request.method,
        request.url,
        request.headers,
        request.body,
        error_text,
      )
      |> result.replace(Nil)
    }
  }
}

pub fn latest_planned_at(db: process.Name(pog.Message), job_id: String) -> Int {
  let connection = pog.named_connection(db)
  let assert Ok(pog.Returned(_, [row])) =
    sql.cron_latest_planned(connection, job_id)
  row.latest_planned_at
}
