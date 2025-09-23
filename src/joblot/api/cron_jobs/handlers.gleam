import clockwork
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/json
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
