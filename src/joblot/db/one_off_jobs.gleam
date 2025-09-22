import glanoid
import gleam/dict
import gleam/erlang/process
import gleam/function
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import joblot/api/error
import joblot/hash
import joblot/sql
import joblot/utils
import pog
import wisp.{type Request as WispRequest}

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
  Response(planned_at: Int, attempted_at: Int, response: ResponseData)
  RequestError(planned_at: Int, attempted_at: Int, error: String)
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
    Response(planned_at, attempted_at, response) -> {
      json.object([
        #("type", json.string("Response")),
        #("planned_at", json.int(planned_at)),
        #("attempted_at", json.int(attempted_at)),
        #("response", response_data_json(response)),
      ])
    }
    RequestError(planned_at, attempted_at, error) -> {
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
) -> Result(OneOffJob, error.ApiError) {
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

  use returned <- result.try(
    result |> result.map_error(error.from_pog_query_error),
  )

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

pub type Filter {
  Filter(user_id: Option(String), tenant_id: Option(String))
}

pub fn filter_from_request(request: WispRequest) -> Option(Filter) {
  let query = wisp.get_query(request)
  let user_id = query |> list.key_find("user_id") |> option.from_result
  let tenant_id = query |> list.key_find("tenant_id") |> option.from_result
  Some(Filter(user_id, tenant_id))
}

pub fn get_one_off_job(
  db: process.Name(pog.Message),
  id: String,
  filter: Option(Filter),
) -> Result(OneOffJob, error.ApiError) {
  let connection = pog.named_connection(db)
  let user_id =
    filter
    |> option.map(fn(filter) { filter.user_id })
    |> option.flatten
    |> option.unwrap("%")

  let tenant_id =
    filter
    |> option.map(fn(filter) { filter.tenant_id })
    |> option.flatten
    |> option.unwrap("%")

  use pog.Returned(_, rows) <- result.try(
    sql.get_one_off_job(connection, id, user_id, tenant_id)
    |> result.map_error(error.from_pog_query_error),
  )

  let ids = rows |> list.map(fn(row) { row.id })

  use attempts <- result.try(get_attempts_for_jobs(db, ids))

  case rows {
    [item] -> {
      let attempts = attempts |> dict.get(item.id) |> result.unwrap([])
      use method <- result.try(
        http.parse_method(item.method)
        |> result.replace_error(error.InternalServerError),
      )
      use url <- result.try(
        uri.parse(item.url) |> result.replace_error(error.InternalServerError),
      )

      Ok(OneOffJob(
        id: item.id,
        created_at: item.created_at,
        request: RequestData(
          method: method,
          url: url,
          headers: item.headers,
          body: item.body,
          timeout_ms: item.timeout_ms,
          non_2xx_is_failure: item.non_2xx_is_failure,
        ),
        user_id: item.user_id |> option.Some,
        tenant_id: item.tenant_id |> option.Some,
        planned_at: item.execute_at,
        maximum_attempts: item.maximum_attempts,
        attempts: attempts,
        completed: item.completed,
      ))
    }
    [] -> Error(error.NotFoundError)
    _ -> panic as "Attempted to get one off job but got multiple rows"
  }
}

pub fn get_one_off_jobs(
  db: process.Name(pog.Message),
  cursor: String,
  filter: Option(Filter),
) -> Result(List(OneOffJob), error.ApiError) {
  let connection = pog.named_connection(db)
  let user_id =
    filter
    |> option.map(fn(filter) { filter.user_id })
    |> option.flatten
    |> option.unwrap("%")

  let tenant_id =
    filter
    |> option.map(fn(filter) { filter.tenant_id })
    |> option.flatten
    |> option.unwrap("%")

  use pog.Returned(_, rows) <- result.try(
    sql.get_one_off_jobs(connection, user_id, tenant_id, cursor, 100)
    |> result.map_error(error.from_pog_query_error),
  )

  let ids = rows |> list.map(fn(row) { row.id })

  use attempts <- result.try(get_attempts_for_jobs(db, ids))

  rows
  |> list.map(fn(row) {
    use method <- result.try(
      http.parse_method(row.method)
      |> result.replace_error(error.InternalServerError),
    )
    use url <- result.try(
      uri.parse(row.url) |> result.replace_error(error.InternalServerError),
    )
    Ok(OneOffJob(
      id: row.id,
      created_at: row.created_at,
      user_id: row.user_id |> option.Some,
      tenant_id: row.tenant_id |> option.Some,
      planned_at: row.execute_at,
      maximum_attempts: row.maximum_attempts,
      attempts: attempts |> dict.get(row.id) |> result.unwrap([]),
      completed: row.completed,
      request: RequestData(
        method: method,
        url: url,
        headers: row.headers,
        body: row.body,
        timeout_ms: row.timeout_ms,
        non_2xx_is_failure: row.non_2xx_is_failure,
      ),
    ))
  })
  |> result.all
}

fn get_attempts_for_jobs(
  db: process.Name(pog.Message),
  ids: List(String),
) -> Result(dict.Dict(String, List(AttemptData)), error.ApiError) {
  let connection = pog.named_connection(db)
  use pog.Returned(_, error_rows) <- result.try(
    sql.get_errored_attempts_for(connection, [], ids)
    |> result.map_error(error.from_pog_query_error),
  )
  use pog.Returned(_, response_rows) <- result.try(
    sql.get_responses_for(connection, [], ids)
    |> result.map_error(error.from_pog_query_error),
  )

  let error_rows_attempts =
    error_rows
    |> list.map(fn(row) {
      #(row.id, RequestError(row.planned_at, row.attempted_at, row.error))
    })
  let response_rows_attempts =
    response_rows
    |> list.map(fn(row) {
      #(
        row.id,
        Response(
          row.planned_at,
          row.attempted_at,
          ResponseData(
            status_code: row.res_status_code,
            headers: row.res_headers,
            body: row.res_body,
            response_time_ms: row.response_time_ms,
          ),
        ),
      )
    })

  let attempts =
    error_rows_attempts
    |> list.append(response_rows_attempts)
    |> list.group(fn(entry) { entry.0 })
    |> dict.map_values(fn(_, list) { list |> list.map(fn(entry) { entry.1 }) })

  Ok(attempts)
}
