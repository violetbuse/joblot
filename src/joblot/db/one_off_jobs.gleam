import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/uri
import joblot/sql
import pog

pub type OneOffJob {
  OneOffJob(
    id: String,
    created_at: Int,
    request: RequestData,
    response: Option(ResponseData),
    user_id: Option(String),
    tenant_id: Option(String),
    maximum_retries: Int,
    attempts: Int,
  )
}

pub type RequestData {
  RequestData(
    method: http.Method,
    url: uri.Uri,
    headers: List(String),
    body: String,
    timeout_ms: Int,
    execute_at: Int,
  )
}

pub type ResponseData {
  ResponseData(
    status_code: Int,
    headers: List(String),
    body: String,
    response_time_ms: Int,
    executed_at: Int,
  )
}

pub fn one_off_job_json(job: OneOffJob) -> json.Json {
  json.object([
    #("id", json.string(job.id)),
    #("created_at", json.int(job.created_at)),
    #("request", request_data_json(job.request)),
    #("response", json.nullable(job.response, response_data_json)),
    #("user_id", json.nullable(job.user_id, json.string)),
    #("tenant_id", json.nullable(job.tenant_id, json.string)),
    #("maximum_retries", json.int(job.maximum_retries)),
    #("attempts", json.int(job.attempts)),
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

fn response_data_json(response: ResponseData) -> json.Json {
  json.object([
    #("status_code", json.int(response.status_code)),
    #("headers", json.array(response.headers, json.string)),
    #("body", json.string(response.body)),
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
    maximum_retries: Option(Int),
  )
}

pub fn create_one_off_job(
  db: process.Name(pog.Message),
  job: CreateOneOffJob,
) -> Result(OneOffJob, pog.QueryError) {
  Ok(OneOffJob(
    id: "test",
    created_at: 0,
    request: RequestData(
      method: job.method,
      url: job.url,
      headers: job.headers,
      body: job.body,
      timeout_ms: job.timeout_ms |> option.unwrap(0),
      execute_at: job.execute_at |> option.unwrap(0),
    ),
    response: None,
    user_id: job.user_id,
    tenant_id: job.tenant_id,
    maximum_retries: job.maximum_retries |> option.unwrap(0),
    attempts: 0,
  ))
}
