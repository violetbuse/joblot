import glanoid
import gleam/dict
import gleam/erlang/process
import gleam/function
import gleam/http
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import joblot/hash
import joblot/sql
import joblot/utils
import pog

pub type OneOffJob {
  OneOffJob(
    id: String,
    created_at: Int,
    request: RequestData,
    user_id: Option(String),
    tenant_id: Option(String),
    planned_at: Int,
    maximum_attempts: Int,
    attempts: List(AttemptData),
    completed: Bool,
  )
}

pub type RequestData {
  RequestData(
    method: http.Method,
    url: uri.Uri,
    headers: List(String),
    body: String,
    timeout_ms: Int,
    non_2xx_is_failure: Bool,
  )
}

pub type AttemptData {
  Success(planned_at: Int, attempted_at: Int, response: ResponseData)
  Failure(planned_at: Int, attempted_at: Int, response: ResponseData)
  Error(planned_at: Int, attempted_at: Int, error: String)
}

pub type ResponseData {
  ResponseData(
    status_code: Int,
    headers: List(String),
    body: String,
    response_time_ms: Int,
  )
}

pub fn one_off_job_json(job: OneOffJob) -> json.Json {
  json.object([
    #("id", json.string(job.id)),
    #("created_at", json.int(job.created_at)),
    #("request", request_data_json(job.request)),
    #("user_id", json.nullable(job.user_id, json.string)),
    #("tenant_id", json.nullable(job.tenant_id, json.string)),
    #("planned_at", json.int(job.planned_at)),
    #("maximum_attempts", json.int(job.maximum_attempts)),
    #("attempts", json.array(job.attempts, attempt_data_json)),
    #("completed", json.bool(job.completed)),
  ])
}

fn request_data_json(request: RequestData) -> json.Json {
  let method = http.method_to_string(request.method)
  let url = uri.to_string(request.url)

  json.object([
    #("method", json.string(method)),
    #("url", json.string(url)),
    #("headers", json.array(request.headers, json.string)),
    #("body", json.string(request.body)),
  ])
}

fn attempt_data_json(attempt: AttemptData) -> json.Json {
  case attempt {
    Success(planned_at, attempted_at, response) -> {
      json.object([
        #("type", json.string("Success")),
        #("planned_at", json.int(planned_at)),
        #("attempted_at", json.int(attempted_at)),
        #("response", response_data_json(response)),
      ])
    }
    Failure(planned_at, attempted_at, response) -> {
      json.object([
        #("type", json.string("Failure")),
        #("planned_at", json.int(planned_at)),
        #("attempted_at", json.int(attempted_at)),
        #("response", response_data_json(response)),
      ])
    }
    Error(planned_at, attempted_at, error) -> {
      json.object([
        #("type", json.string("Error")),
        #("planned_at", json.int(planned_at)),
        #("attempted_at", json.int(attempted_at)),
        #("error", json.string(error)),
      ])
    }
  }
}

fn response_data_json(response: ResponseData) -> json.Json {
  json.object([
    #("status_code", json.int(response.status_code)),
    #("headers", json.array(response.headers, json.string)),
    #("body", json.string(response.body)),
    #("response_time_ms", json.int(response.response_time_ms)),
  ])
}

pub type CreateOneOffJob {
  CreateOneOffJob(
    method: http.Method,
    url: uri.Uri,
    headers: List(String),
    body: String,
    metadata: List(#(String, String)),
    user_id: Option(String),
    tenant_id: Option(String),
    timeout_ms: Option(Int),
    execute_at: Option(Int),
    maximum_attempts: Option(Int),
    non_2xx_is_failure: Option(Bool),
  )
}

pub fn create_one_off_job(
  db: process.Name(pog.Message),
  job: CreateOneOffJob,
) -> Result(OneOffJob, pog.QueryError) {
  let connection = pog.named_connection(db)

  let assert Ok(nanoid) = glanoid.make_generator(glanoid.default_alphabet)
  let id = "one_off_job_" <> nanoid(21)
  let hash = hash.create_shard_key_hash(id)

  let user_id = job.user_id |> option.unwrap("")
  let tenant_id = job.tenant_id |> option.unwrap("")
  let metadata =
    job.metadata
    |> dict.from_list
    |> json.dict(function.identity, json.string)

  let method = http.method_to_string(job.method)
  let url = uri.to_string(job.url)
  let headers = job.headers
  let body = job.body

  let execute_at = job.execute_at |> option.unwrap(utils.get_unix_timestamp())
  let maximum_attempts = job.maximum_attempts |> option.unwrap(1)
  let non_2xx_is_failure = job.non_2xx_is_failure |> option.unwrap(True)
  let timeout_ms = job.timeout_ms |> option.unwrap(10_000)

  let result =
    sql.create_one_off_job(
      connection,
      id,
      hash,
      utils.get_unix_timestamp(),
      user_id,
      tenant_id,
      metadata,
      method,
      url,
      headers,
      body,
      execute_at,
      maximum_attempts,
      non_2xx_is_failure,
      timeout_ms,
    )

  use returned <- result.try(result)

  case returned {
    pog.Returned(_, [single_row]) ->
      Ok(OneOffJob(
        id: single_row.id,
        created_at: single_row.created_at,
        request: RequestData(
          method: job.method,
          url: job.url,
          headers: single_row.headers,
          body: single_row.body,
          timeout_ms: single_row.timeout_ms,
          non_2xx_is_failure: single_row.non_2xx_is_failure,
        ),
        user_id: single_row.user_id |> option.Some,
        tenant_id: single_row.tenant_id |> option.Some,
        planned_at: single_row.execute_at,
        maximum_attempts: single_row.maximum_attempts,
        attempts: [],
        completed: single_row.completed,
      ))
    _ -> panic as "Attempted to create one off job but got multiple rows"
  }
}

pub type TenancyFilter {
  TenancyFilter(user_id: Option(String), tenant_id: Option(String))
}
// pub fn get_one_off_job(
//   db: process.Name(pog.Message),
//   id: String,
//   filter: Option(TenancyFilter),
// ) -> Result(OneOffJob, pog.QueryError) {
//   let connection = pog.named_connection(db)
//   let user_id =
//     filter
//     |> option.map(fn(filter) { filter.user_id })
//     |> option.flatten
//     |> option.unwrap("%")

//   let tenant_id =
//     filter
//     |> option.map(fn(filter) { filter.tenant_id })
//     |> option.flatten
//     |> option.unwrap("%")

//   case sql.get_one_off_job(connection, id, user_id, tenant_id) {
//     pog.Returned(_, [single_row]) ->
//       Ok(OneOffJob(
//         id: single_row.id,
//         created_at: single_row.created_at,
//         request: RequestData(
//           method: single_row.method,
//           url: single_row.url,
//           headers: single_row.headers,
//           body: single_row.body,
//           timeout_ms: single_row.timeout_ms,
//           non_2xx_is_failure: single_row.non_2xx_is_failure,
//         ),
//       ))
//   }
// }
