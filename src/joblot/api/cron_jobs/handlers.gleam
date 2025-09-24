import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result

import joblot/api/cron_jobs/data
import joblot/api/error
import joblot/api/utils
import pog
import wisp.{type Request, type Response}

type DB =
  process.Name(pog.Message)

pub fn cron_job_router(
  path_segments: List(String),
  request: Request,
  db: DB,
) -> Response {
  case request.method, path_segments {
    http.Post, [] -> handle_create_cron_job(request, db)
    http.Delete, [id] -> handle_delete_cron_job(id, request, db)
    http.Get, [id] -> handle_get_cron_job(id, request, db)
    http.Get, [] -> handle_list_cron_jobs(request, db)
    _, _ -> error.to_response(error.NotFoundError)
  }
}

fn create_cron_job_decoder() -> decode.Decoder(data.CreateCronJob) {
  use cron <- decode.field("cron", utils.decode_cron())
  use method <- decode.field("method", utils.decode_http_method())
  use url <- decode.field("url", utils.decode_url())
  use headers <- utils.decode_headers()
  use body <- decode.optional_field("body", "", decode.string)
  use metadata <- utils.decode_metadata()
  use user_id <- utils.decode_optional_string_field("user_id")
  use tenant_id <- utils.decode_optional_string_field("tenant_id")
  use timeout_ms <- utils.decode_optional_int_field("timeout_ms")
  use maximum_attempts <- utils.decode_optional_int_field("maximum_attempts")
  use non_2xx_is_failure <- utils.decode_optional_bool_field(
    "non_2xx_is_failure",
  )
  decode.success(data.CreateCronJob(
    cron:,
    method:,
    url:,
    headers:,
    body:,
    metadata:,
    user_id:,
    tenant_id:,
    timeout_ms:,
    maximum_attempts:,
    non_2xx_is_failure:,
  ))
}

pub fn handle_create_cron_job(request: Request, db: DB) -> Response {
  use json <- wisp.require_json(request)
  let result = {
    use create_cron_job <- error.require_decoded(
      json,
      create_cron_job_decoder(),
    )
    use created_job <- result.try(data.create_cron_job(db, create_cron_job))
    Ok(created_job)
  }

  case result {
    Error(error) -> {
      error.to_response(error)
    }
    Ok(created_job) -> {
      wisp.response(200)
      |> wisp.json_body(data.cron_job_json(created_job) |> json.to_string)
    }
  }
}

pub fn handle_delete_cron_job(id: String, request: Request, db: DB) -> Response {
  let result = {
    let filter = data.filter_from_request(request)
    use deleted_job <- result.try(data.delete_cron_job(db, id, filter))
    Ok(deleted_job)
  }

  case result {
    Error(error) -> {
      error.to_response(error)
    }
    Ok(deleted_job) -> {
      let response_json = case deleted_job {
        None ->
          json.object([
            #("deleted_job_count", json.int(0)),
            #("data", json.null()),
          ])
        Some(job_data) ->
          json.object([
            #("deleted_job_count", json.int(1)),
            #("data", data.cron_job_json(job_data)),
          ])
      }

      wisp.response(200)
      |> wisp.json_body(json.to_string(response_json))
    }
  }
}

pub fn handle_get_cron_job(id: String, request: Request, db: DB) -> Response {
  let result = {
    let filter = data.filter_from_request(request)
    use cron_job <- result.try(data.get_cron_job(db, id, filter))
    Ok(cron_job)
  }

  case result {
    Error(error) -> {
      error.to_response(error)
    }
    Ok(cron_job) -> {
      wisp.response(200)
      |> wisp.json_body(data.cron_job_json(cron_job) |> json.to_string)
    }
  }
}

pub fn handle_list_cron_jobs(request: Request, db: DB) -> Response {
  let result = {
    let cursor =
      wisp.get_query(request) |> list.key_find("cursor") |> result.unwrap("")

    let filter = data.filter_from_request(request)

    use cron_jobs <- result.try(data.list_cron_jobs(db, cursor, filter))
    Ok(cron_jobs)
  }

  case result {
    Error(error) -> {
      error.to_response(error)
    }
    Ok(cron_jobs) -> {
      let next_page_cursor =
        cron_jobs
        |> list.last
        |> result.map(fn(cron_job) { cron_job.id })
        |> option.from_result

      let response_json =
        json.object([
          #("next_page_cursor", json.nullable(next_page_cursor, json.string)),
          #("data", json.array(cron_jobs, data.cron_job_json)),
        ])

      wisp.response(200)
      |> wisp.json_body(json.to_string(response_json))
    }
  }
}
