import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import joblot/api/error
import joblot/api/utils
import joblot/db/one_off_jobs
import pog
import wisp.{type Request, type Response}

type DB =
  process.Name(pog.Message)

fn create_one_off_job_decoder() -> decode.Decoder(one_off_jobs.CreateOneOffJob) {
  use method <- decode.field("method", utils.decode_http_method())
  use url <- decode.field("url", utils.decode_url())
  use headers <- utils.decode_headers()
  use body <- decode.optional_field("body", "", decode.string)
  use metadata <- utils.decode_metadata()
  use user_id <- utils.decode_optional_string_field("user_id")
  use tenant_id <- utils.decode_optional_string_field("tenant_id")
  use timeout_ms <- utils.decode_optional_int_field("timeout_ms")
  use execute_at <- utils.decode_optional_int_field("execute_at")
  use maximum_attempts <- utils.decode_optional_int_field("maximum_attempts")
  use non_2xx_is_failure <- utils.decode_optional_bool_field(
    "non_2xx_is_failure",
  )
  decode.success(one_off_jobs.CreateOneOffJob(
    method:,
    url:,
    headers:,
    body:,
    metadata:,
    user_id:,
    tenant_id:,
    timeout_ms:,
    execute_at:,
    maximum_attempts:,
    non_2xx_is_failure:,
  ))
}

pub fn handle_create_one_off_job(request: Request, db: DB) -> Response {
  use json <- wisp.require_json(request)
  let result = {
    use create_one_off <- error.require_decoded(
      json,
      create_one_off_job_decoder(),
    )
    use created_job <- result.try(one_off_jobs.create_one_off_job(
      db,
      create_one_off,
    ))

    Ok(created_job)
  }

  case result {
    Error(error) -> {
      error.to_response(error)
    }
    Ok(created_job) -> {
      wisp.response(200)
      |> wisp.json_body(
        one_off_jobs.one_off_job_json(created_job)
        |> json.to_string,
      )
    }
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
  let result = {
    let filter = one_off_jobs.filter_from_request(request)
    use one_off_job <- result.try(one_off_jobs.get_one_off_job(db, id, filter))
    Ok(one_off_job)
  }

  case result {
    Error(error) -> {
      error.to_response(error)
    }
    Ok(one_off_job) -> {
      wisp.response(200)
      |> wisp.json_body(
        one_off_jobs.one_off_job_json(one_off_job) |> json.to_string,
      )
    }
  }
}

pub fn handle_list_one_off_jobs(request: Request, db: DB) -> Response {
  let result = {
    let cursor =
      wisp.get_query(request) |> list.key_find("cursor") |> result.unwrap("")

    let filter = one_off_jobs.filter_from_request(request)

    use one_off_jobs <- result.try(one_off_jobs.get_one_off_jobs(
      db,
      cursor,
      filter,
    ))
    Ok(one_off_jobs)
  }

  case result {
    Error(error) -> {
      error.to_response(error)
    }
    Ok(one_off_jobs) -> {
      let next_page_cursor =
        one_off_jobs
        |> list.last
        |> result.map(fn(one_off_job) { one_off_job.id })
        |> option.from_result

      let response_json =
        json.object([
          #("next_page_cursor", json.nullable(next_page_cursor, json.string)),
          #("data", json.array(one_off_jobs, one_off_jobs.one_off_job_json)),
        ])

      wisp.response(200)
      |> wisp.json_body(json.to_string(response_json))
    }
  }
}
