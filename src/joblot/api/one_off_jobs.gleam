import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import joblot/api/utils
import pog
import wisp.{type Request, type Response}

type DB =
  process.Name(pog.Message)

type CreateOneOffJob {
  CreateOneOffJob(
    metadata: List(#(String, String)),
    user_id: String,
    tenant_id: String,
    method: http.Method,
    url: String,
    headers: List(#(String, String)),
    body: String,
    timeout_ms: Int,
    execute_at: Int,
    maximum_retries: Int,
  )
}

fn create_one_off_job_decoder() -> decode.Decoder(CreateOneOffJob) {
  use metadata <- decode.optional_field("metadata", [], utils.decode_metadata())
  use user_id <- decode.optional_field(
    "user_id",
    None,
    decode.string |> decode.map(option.Some),
  )
  use tenant_id <- decode.optional_field(
    "tenant_id",
    None,
    decode.string |> decode.map(option.Some),
  )
  use method <- decode.field("method", decode.string)
  use url <- decode.field("url", decode.string)
  use headers <- decode.optional_field(
    "headers",
    [],
    decode.dict(decode.string, decode.string)
      |> decode.map(dict.to_list)
      |> decode.map(list.map(_, fn(tuple) { tuple.0 <> ":" <> tuple.1 })),
  )
  use body <- decode.optional_field("body", "", decode.string)
  use timeout_ms <- decode.field("timeout_ms", decode.int)
  use execute_at <- decode.field("execute_at", decode.int)
  use maximum_retries <- decode.field("maximum_retries", decode.int)
  todo
}

pub fn handle_create_one_off_job(request: Request, db: DB) -> Response {
  use json <- wisp.require_json(request)
  let result = {
    use input <- result.try(decode.run(json, create_one_off_job_decoder()))

    Ok(
      json.object([
        #("message", json.string("CreateOneOffJob")),
      ])
      |> json.to_string,
    )
  }

  case result {
    Ok(json) -> wisp.json_response(json, 200)
    Error(_) -> wisp.bad_request("Invalid request")
  }
}

pub fn handle_update_one_off_job(
  id: String,
  request: Request,
  db: DB,
) -> Response {
  wisp.ok()
}

pub fn handle_delete_one_off_job(
  id: String,
  request: Request,
  db: DB,
) -> Response {
  wisp.ok()
}

pub fn handle_get_one_off_job(id: String, request: Request, db: DB) -> Response {
  wisp.ok()
}

pub fn handle_list_one_off_jobs(request: Request, db: DB) -> Response {
  wisp.ok()
}
