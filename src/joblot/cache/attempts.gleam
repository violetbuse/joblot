import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import joblot/cache/sql
import pog

pub type Attempt {
  SuccessfulRequest(attempted_at: Int, planned_at: Int, response: Response)
  FailedRequest(attempted_at: Int, planned_at: Int, response: Response)
  RequestError(attempted_at: Int, planned_at: Int, error: String)
}

pub type Response {
  Response(
    status_code: Int,
    headers: List(String),
    body: String,
    response_time_ms: Int,
  )
}

pub fn get_attempts(
  db: process.Name(pog.Message),
  planned_at: Int,
  job_id: String,
  timeout_ms: Int,
) -> Result(List(Attempt), String) {
  let data_subject = process.new_subject()

  process.spawn(fn() {
    let errors_subject = process.new_subject()
    let response_subject = process.new_subject()

    process.spawn(fn() {
      pog.named_connection(db)
      |> sql.list_errored_attempts(planned_at, job_id)
      |> result.replace_error(
        "Could not fetch errored attempts for job id: " <> job_id,
      )
      |> process.send(errors_subject, _)
    })

    process.spawn(fn() {
      pog.named_connection(db)
      |> sql.list_responses(planned_at, job_id)
      |> result.replace_error(
        "Could not fetch responses for job_id: " <> job_id,
      )
      |> process.send(response_subject, _)
    })

    let error_result =
      process.receive(errors_subject, timeout_ms)
      |> result.replace_error(
        "Fetching error attempts for job id: " <> job_id <> " timed out.",
      )
      |> result.flatten
    let response_result =
      process.receive(response_subject, timeout_ms)
      |> result.replace_error(
        "Fetching responses for job id: " <> job_id <> " timed out.",
      )
      |> result.flatten

    let result = case error_result, response_result {
      Ok(errors), Ok(responses) -> Ok(#(errors, responses))
      Error(errors_error), Error(responses_error) ->
        Error(
          "Fetching errors and responses failed: "
          <> errors_error
          <> ", "
          <> responses_error,
        )
      Error(errors_error), _ -> Error(errors_error)
      _, Error(responses_error) -> Error(responses_error)
    }

    process.send(data_subject, result)
  })

  use #(pog.Returned(_, errored), pog.Returned(_, responses)) <- result.try(
    process.receive(data_subject, timeout_ms + 100)
    |> result.replace_error(
      "Fetching errors and responses from database timed out",
    )
    |> result.flatten,
  )

  let errored_attempts =
    list.map(errored, fn(err) -> Attempt {
      RequestError(
        attempted_at: err.attempted_at,
        planned_at: err.planned_at,
        error: err.error,
      )
    })

  let response_attempts =
    list.map(responses, fn(res) -> Attempt {
      let response =
        Response(
          status_code: res.res_status_code,
          headers: res.res_headers,
          body: res.res_body,
          response_time_ms: res.response_time_ms,
        )

      case res.success {
        True ->
          SuccessfulRequest(
            attempted_at: res.attempted_at,
            planned_at: res.planned_at,
            response: response,
          )
        False ->
          FailedRequest(
            attempted_at: res.attempted_at,
            planned_at: res.planned_at,
            response: response,
          )
      }
    })

  list.append(errored_attempts, response_attempts)
  |> list.sort(fn(a, b) {
    int.compare(a.attempted_at, b.attempted_at) |> order.negate
  })
  |> Ok
}
