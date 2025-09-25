import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, Some}
import gleam/order
import gleam/result
import joblot/api/error
import joblot/api/sql
import pog

pub type AttemptData {
  SuccessfulRequest(
    planned_at: Int,
    attempted_at: Int,
    request: AttemptRequestData,
    response: ResponseData,
  )
  FailedRequest(
    planned_at: Int,
    attempted_at: Int,
    request: AttemptRequestData,
    response: ResponseData,
  )
  RequestError(
    planned_at: Int,
    attempted_at: Int,
    request: AttemptRequestData,
    error: String,
  )
}

pub type AttemptRequestData {
  AttemptRequestData(
    method: String,
    url: String,
    headers: List(String),
    body: String,
  )
}

pub type ResponseData {
  ResponseData(
    status_code: Int,
    headers: List(String),
    body: String,
    response_time_ms: Int,
  )
}

pub fn attempt_data_json(attempt: AttemptData) -> json.Json {
  case attempt {
    SuccessfulRequest(planned_at, attempted_at, request, response) -> {
      json.object([
        #("type", json.string("successful_request")),
        #("planned_at", json.int(planned_at)),
        #("attempted_at", json.int(attempted_at)),
        #("request", request_data_json(request)),
        #("response", response_data_json(response)),
        #("error", json.null()),
      ])
    }
    FailedRequest(planned_at, attempted_at, request, response) -> {
      json.object([
        #("type", json.string("failed_request")),
        #("planned_at", json.int(planned_at)),
        #("attempted_at", json.int(attempted_at)),
        #("request", request_data_json(request)),
        #("response", response_data_json(response)),
        #("error", json.null()),
      ])
    }
    RequestError(planned_at, attempted_at, request, error) -> {
      json.object([
        #("type", json.string("error")),
        #("planned_at", json.int(planned_at)),
        #("attempted_at", json.int(attempted_at)),
        #("request", request_data_json(request)),
        #("response", json.null()),
        #("error", json.string(error)),
      ])
    }
  }
}

fn request_data_json(request: AttemptRequestData) -> json.Json {
  json.object([
    #("method", json.string(request.method)),
    #("url", json.string(request.url)),
    #("headers", json.array(request.headers, json.string)),
    #("body", json.string(request.body)),
  ])
}

fn response_data_json(response: ResponseData) -> json.Json {
  json.object([
    #("status_code", json.int(response.status_code)),
    #("headers", json.array(response.headers, json.string)),
    #("body", json.string(response.body)),
    #("response_time_ms", json.int(response.response_time_ms)),
  ])
}

pub fn get_attempts_for_jobs(
  db: process.Name(pog.Message),
  ids: List(String),
) -> Result(dict.Dict(String, List(AttemptData)), error.ApiError) {
  let connection = pog.named_connection(db)
  use pog.Returned(_, error_rows) <- result.try(
    sql.get_errored_attempts(connection, ids, 300)
    |> result.map_error(error.from_pog_query_error),
  )
  use pog.Returned(_, response_rows) <- result.try(
    sql.get_responses(connection, ids, 300)
    |> result.map_error(error.from_pog_query_error),
  )

  let error_rows_attempts =
    error_rows
    |> list.map(fn(row) {
      let request =
        AttemptRequestData(
          method: row.method,
          url: row.url,
          headers: row.req_headers,
          body: row.req_body,
        )

      #(
        extract_job_id(row.one_off_job_id, row.cron_job_id),
        RequestError(row.planned_at, row.attempted_at, request, row.error),
      )
    })
  let response_rows_attempts =
    response_rows
    |> list.map(fn(row) {
      let job_id = extract_job_id(row.one_off_job_id, row.cron_job_id)
      let request =
        AttemptRequestData(
          method: row.method,
          url: row.url,
          headers: row.req_headers,
          body: row.req_body,
        )

      let response =
        ResponseData(
          status_code: row.res_status_code,
          headers: row.res_headers,
          body: row.res_body,
          response_time_ms: row.response_time_ms,
        )

      case row.success {
        True -> #(
          job_id,
          SuccessfulRequest(row.planned_at, row.attempted_at, request, response),
        )
        False -> #(
          job_id,
          FailedRequest(row.planned_at, row.attempted_at, request, response),
        )
      }
    })

  let attempts =
    error_rows_attempts
    |> list.append(response_rows_attempts)
    |> list.group(fn(entry) { entry.0 })
    |> dict.map_values(fn(_, list) {
      list
      |> list.map(fn(entry) { entry.1 })
      |> list.sort(fn(a, b) {
        case int.compare(a.attempted_at, b.attempted_at) {
          order.Eq -> order.Eq
          order.Lt -> order.Gt
          order.Gt -> order.Lt
        }
      })
    })

  Ok(attempts)
}

fn extract_job_id(id_one: Option(String), id_two: Option(String)) -> String {
  case id_one, id_two {
    Some(id), _ -> id
    _, Some(id) -> id
    _, _ -> panic as "Attempted to extract job id but got no ids"
  }
}
