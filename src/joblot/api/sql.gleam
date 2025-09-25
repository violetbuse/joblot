//// This module contains the code to run the sql queries defined in
//// `./src/joblot/api/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// A row you get from running the `get_errored_attempts` query
/// defined in `./src/joblot/api/sql/get_errored_attempts.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetErroredAttemptsRow {
  GetErroredAttemptsRow(
    id: String,
    planned_at: Int,
    attempted_at: Int,
    user_id: String,
    tenant_id: String,
    one_off_job_id: Option(String),
    cron_job_id: Option(String),
    error: String,
    method: String,
    url: String,
    req_headers: List(String),
    req_body: String,
  )
}

/// Runs the `get_errored_attempts` query
/// defined in `./src/joblot/api/sql/get_errored_attempts.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_errored_attempts(
  db: pog.Connection,
  arg_1: List(String),
  arg_2: Int,
) -> Result(pog.Returned(GetErroredAttemptsRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use planned_at <- decode.field(1, decode.int)
    use attempted_at <- decode.field(2, decode.int)
    use user_id <- decode.field(3, decode.string)
    use tenant_id <- decode.field(4, decode.string)
    use one_off_job_id <- decode.field(5, decode.optional(decode.string))
    use cron_job_id <- decode.field(6, decode.optional(decode.string))
    use error <- decode.field(7, decode.string)
    use method <- decode.field(8, decode.string)
    use url <- decode.field(9, decode.string)
    use req_headers <- decode.field(10, decode.list(decode.string))
    use req_body <- decode.field(11, decode.string)
    decode.success(GetErroredAttemptsRow(
      id:,
      planned_at:,
      attempted_at:,
      user_id:,
      tenant_id:,
      one_off_job_id:,
      cron_job_id:,
      error:,
      method:,
      url:,
      req_headers:,
      req_body:,
    ))
  }

  "SELECT *
FROM errored_attempts
WHERE one_off_job_id = ANY($1::TEXT [])
    OR cron_job_id = ANY($1::TEXT [])
ORDER BY attempted_at DESC
LIMIT $2;"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_responses` query
/// defined in `./src/joblot/api/sql/get_responses.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetResponsesRow {
  GetResponsesRow(
    id: String,
    planned_at: Int,
    attempted_at: Int,
    user_id: String,
    tenant_id: String,
    one_off_job_id: Option(String),
    cron_job_id: Option(String),
    method: String,
    url: String,
    req_headers: List(String),
    req_body: String,
    res_status_code: Int,
    res_headers: List(String),
    res_body: String,
    response_time_ms: Int,
    success: Bool,
  )
}

/// Runs the `get_responses` query
/// defined in `./src/joblot/api/sql/get_responses.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_responses(
  db: pog.Connection,
  arg_1: List(String),
  arg_2: Int,
) -> Result(pog.Returned(GetResponsesRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use planned_at <- decode.field(1, decode.int)
    use attempted_at <- decode.field(2, decode.int)
    use user_id <- decode.field(3, decode.string)
    use tenant_id <- decode.field(4, decode.string)
    use one_off_job_id <- decode.field(5, decode.optional(decode.string))
    use cron_job_id <- decode.field(6, decode.optional(decode.string))
    use method <- decode.field(7, decode.string)
    use url <- decode.field(8, decode.string)
    use req_headers <- decode.field(9, decode.list(decode.string))
    use req_body <- decode.field(10, decode.string)
    use res_status_code <- decode.field(11, decode.int)
    use res_headers <- decode.field(12, decode.list(decode.string))
    use res_body <- decode.field(13, decode.string)
    use response_time_ms <- decode.field(14, decode.int)
    use success <- decode.field(15, decode.bool)
    decode.success(GetResponsesRow(
      id:,
      planned_at:,
      attempted_at:,
      user_id:,
      tenant_id:,
      one_off_job_id:,
      cron_job_id:,
      method:,
      url:,
      req_headers:,
      req_body:,
      res_status_code:,
      res_headers:,
      res_body:,
      response_time_ms:,
      success:,
    ))
  }

  "SELECT *
FROM responses
WHERE one_off_job_id = ANY($1::TEXT [])
    OR cron_job_id = ANY($1::TEXT [])
ORDER BY attempted_at DESC
LIMIT $2;"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
