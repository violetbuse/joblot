import clockwork
import glanoid
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/function
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import joblot/api/cron_jobs/sql
import joblot/api/error
import joblot/hash
import joblot/utils
import pog

pub type CronJob {
  CronJob(
    id: String,
    created_at: Int,
    request: RequestData,
    user_id: Option(String),
    tenant_id: Option(String),
    metadata: List(#(String, String)),
    cron: String,
    maximum_attempts: Int,
    attempts: List(AttemptData),
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

pub fn cron_job_json(job: CronJob) -> json.Json {
  json.object([
    #("id", json.string(job.id)),
    #("created_at", json.int(job.created_at)),
    #("request", request_data_json(job.request)),
    #("user_id", json.nullable(job.user_id, json.string)),
    #("tenant_id", json.nullable(job.tenant_id, json.string)),
    #(
      "metadata",
      json.dict(job.metadata |> dict.from_list, function.identity, json.string),
    ),
    #("cron", json.string(job.cron)),
    #("maximum_attempts", json.int(job.maximum_attempts)),
    #("attempts", json.array(job.attempts, attempt_data_json)),
  ])
}

fn request_data_json(request: RequestData) -> json.Json {
  json.object([
    #("method", json.string(http.method_to_string(request.method))),
    #("url", json.string(uri.to_string(request.url))),
    #("headers", json.array(request.headers, json.string)),
    #("body", json.string(request.body)),
    #("timeout_ms", json.int(request.timeout_ms)),
    #("non_2xx_is_failure", json.bool(request.non_2xx_is_failure)),
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

pub type CreateCronJob {
  CreateCronJob(
    cron: clockwork.Cron,
    method: http.Method,
    url: uri.Uri,
    headers: List(String),
    body: String,
    metadata: List(#(String, String)),
    user_id: Option(String),
    tenant_id: Option(String),
    timeout_ms: Option(Int),
    maximum_attempts: Option(Int),
    non_2xx_is_failure: Option(Bool),
  )
}

pub fn create_cron_job(
  db: process.Name(pog.Message),
  job: CreateCronJob,
) -> Result(CronJob, error.ApiError) {
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

  let cron = clockwork.to_string(job.cron)
  let maximum_attempts = job.maximum_attempts |> option.unwrap(1)
  let non_2xx_is_failure = job.non_2xx_is_failure |> option.unwrap(True)
  let timeout_ms = job.timeout_ms |> option.unwrap(10_000)

  let insert_result =
    sql.create_cron_job(
      connection,
      id,
      hash,
      user_id,
      tenant_id,
      metadata,
      cron,
      method,
      url,
      headers,
      body,
      maximum_attempts,
      non_2xx_is_failure,
      timeout_ms,
    )

  use returned <- result.try(
    insert_result |> result.map_error(error.from_pog_query_error),
  )

  case returned {
    pog.Returned(_, [single_row]) ->
      Ok(
        CronJob(
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
          metadata: job.metadata,
          cron: single_row.cron,
          maximum_attempts: single_row.maximum_attempts,
          attempts: [],
        ),
      )
    _ -> panic as "Attempted to create cron job but got multiple rows"
  }
}
