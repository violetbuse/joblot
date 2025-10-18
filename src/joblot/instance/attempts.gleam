import glanoid
import gleam/bool
import gleam/erlang/process
import gleam/float
import gleam/http
import gleam/int
import gleam/list
import gleam/result
import gleam/uri
import joblot/executor
import joblot/instance/sql
import pog

pub type JobType {
  OneOffJob
  CronJob
}

/// attempts is attempted_at unix timestamp in seconds
/// delay in seconds
/// factor is the factor by which the delay is multiplied
/// maximum is the maximum delay in seconds
pub fn next_retry_time(
  attempts attempts: List(Int),
  planned planned_at: Int,
  initial delay: Int,
  factor factor: Float,
  maximum maximum: Int,
) -> Int {
  let attempt_count = attempts |> list.length
  let last_attempt_time =
    attempts
    |> list.last
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

pub fn save_attempt(
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

  let method = request.method |> http.method_to_string
  let url = request.url |> uri.to_string
  let headers = request.headers |> list.map(fn(h) { h.0 <> ":" <> h.1 })

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
        method,
        url,
        headers,
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
        method,
        url,
        headers,
        request.body,
        error_text,
      )
      |> result.replace(Nil)
    }
  }
}
