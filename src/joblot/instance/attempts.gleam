import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/result
import joblot/instance/sql
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
