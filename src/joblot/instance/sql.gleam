//// This module contains the code to run the sql queries defined in
//// `./src/joblot/instance/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// A row you get from running the `get_cron_job` query
/// defined in `./src/joblot/instance/sql/get_cron_job.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetCronJobRow {
  GetCronJobRow(
    id: String,
    hash: Int,
    created_at: Int,
    user_id: String,
    tenant_id: String,
    metadata: String,
    cron: String,
    method: String,
    url: String,
    headers: List(String),
    body: String,
    maximum_attempts: Int,
    non_2xx_is_failure: Bool,
    timeout_ms: Int,
  )
}

/// Runs the `get_cron_job` query
/// defined in `./src/joblot/instance/sql/get_cron_job.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_cron_job(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(GetCronJobRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use hash <- decode.field(1, decode.int)
    use created_at <- decode.field(2, decode.int)
    use user_id <- decode.field(3, decode.string)
    use tenant_id <- decode.field(4, decode.string)
    use metadata <- decode.field(5, decode.string)
    use cron <- decode.field(6, decode.string)
    use method <- decode.field(7, decode.string)
    use url <- decode.field(8, decode.string)
    use headers <- decode.field(9, decode.list(decode.string))
    use body <- decode.field(10, decode.string)
    use maximum_attempts <- decode.field(11, decode.int)
    use non_2xx_is_failure <- decode.field(12, decode.bool)
    use timeout_ms <- decode.field(13, decode.int)
    decode.success(GetCronJobRow(
      id:,
      hash:,
      created_at:,
      user_id:,
      tenant_id:,
      metadata:,
      cron:,
      method:,
      url:,
      headers:,
      body:,
      maximum_attempts:,
      non_2xx_is_failure:,
      timeout_ms:,
    ))
  }

  "SELECT *
FROM cron_jobs
WHERE id = $1;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_one_off_job` query
/// defined in `./src/joblot/instance/sql/get_one_off_job.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetOneOffJobRow {
  GetOneOffJobRow(
    id: String,
    hash: Int,
    created_at: Int,
    user_id: String,
    tenant_id: String,
    metadata: String,
    method: String,
    url: String,
    headers: List(String),
    body: String,
    execute_at: Int,
    maximum_attempts: Int,
    non_2xx_is_failure: Bool,
    completed: Bool,
    timeout_ms: Int,
  )
}

/// Runs the `get_one_off_job` query
/// defined in `./src/joblot/instance/sql/get_one_off_job.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_one_off_job(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(GetOneOffJobRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use hash <- decode.field(1, decode.int)
    use created_at <- decode.field(2, decode.int)
    use user_id <- decode.field(3, decode.string)
    use tenant_id <- decode.field(4, decode.string)
    use metadata <- decode.field(5, decode.string)
    use method <- decode.field(6, decode.string)
    use url <- decode.field(7, decode.string)
    use headers <- decode.field(8, decode.list(decode.string))
    use body <- decode.field(9, decode.string)
    use execute_at <- decode.field(10, decode.int)
    use maximum_attempts <- decode.field(11, decode.int)
    use non_2xx_is_failure <- decode.field(12, decode.bool)
    use completed <- decode.field(13, decode.bool)
    use timeout_ms <- decode.field(14, decode.int)
    decode.success(GetOneOffJobRow(
      id:,
      hash:,
      created_at:,
      user_id:,
      tenant_id:,
      metadata:,
      method:,
      url:,
      headers:,
      body:,
      execute_at:,
      maximum_attempts:,
      non_2xx_is_failure:,
      completed:,
      timeout_ms:,
    ))
  }

  "SELECT *
FROM one_off_jobs
WHERE id = $1;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `insert_error_for_cron` query
/// defined in `./src/joblot/instance/sql/insert_error_for_cron.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_error_for_cron(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: Int,
  arg_4: String,
  arg_5: String,
  arg_6: String,
  arg_7: String,
  arg_8: String,
  arg_9: List(String),
  arg_10: String,
  arg_11: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "INSERT INTO errored_attempts (
        id,
        planned_at,
        attempted_at,
        user_id,
        tenant_id,
        cron_job_id,
        method,
        url,
        req_headers,
        req_body,
        error
    )
VALUES (
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8,
        $9,
        $10,
        $11
    );"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.text(arg_6))
  |> pog.parameter(pog.text(arg_7))
  |> pog.parameter(pog.text(arg_8))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_9))
  |> pog.parameter(pog.text(arg_10))
  |> pog.parameter(pog.text(arg_11))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `insert_error_for_one_off` query
/// defined in `./src/joblot/instance/sql/insert_error_for_one_off.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_error_for_one_off(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: Int,
  arg_4: String,
  arg_5: String,
  arg_6: String,
  arg_7: String,
  arg_8: String,
  arg_9: List(String),
  arg_10: String,
  arg_11: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "INSERT INTO errored_attempts (
        id,
        planned_at,
        attempted_at,
        user_id,
        tenant_id,
        one_off_job_id,
        method,
        url,
        req_headers,
        req_body,
        error
    )
VALUES (
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8,
        $9,
        $10,
        $11
    );"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.text(arg_6))
  |> pog.parameter(pog.text(arg_7))
  |> pog.parameter(pog.text(arg_8))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_9))
  |> pog.parameter(pog.text(arg_10))
  |> pog.parameter(pog.text(arg_11))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `insert_response_for_cron` query
/// defined in `./src/joblot/instance/sql/insert_response_for_cron.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_response_for_cron(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: Int,
  arg_4: String,
  arg_5: String,
  arg_6: String,
  arg_7: String,
  arg_8: String,
  arg_9: List(String),
  arg_10: String,
  arg_11: Int,
  arg_12: List(String),
  arg_13: String,
  arg_14: Int,
  arg_15: Bool,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "INSERT INTO responses (
        id,
        planned_at,
        attempted_at,
        user_id,
        tenant_id,
        cron_job_id,
        method,
        url,
        req_headers,
        req_body,
        res_status_code,
        res_headers,
        res_body,
        response_time_ms,
        success
    )
VALUES (
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8,
        $9,
        $10,
        $11,
        $12,
        $13,
        $14,
        $15
    );"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.text(arg_6))
  |> pog.parameter(pog.text(arg_7))
  |> pog.parameter(pog.text(arg_8))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_9))
  |> pog.parameter(pog.text(arg_10))
  |> pog.parameter(pog.int(arg_11))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_12))
  |> pog.parameter(pog.text(arg_13))
  |> pog.parameter(pog.int(arg_14))
  |> pog.parameter(pog.bool(arg_15))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `insert_response_for_one_off` query
/// defined in `./src/joblot/instance/sql/insert_response_for_one_off.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_response_for_one_off(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: Int,
  arg_4: String,
  arg_5: String,
  arg_6: String,
  arg_7: String,
  arg_8: String,
  arg_9: List(String),
  arg_10: String,
  arg_11: Int,
  arg_12: List(String),
  arg_13: String,
  arg_14: Int,
  arg_15: Bool,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "INSERT INTO responses (
        id,
        planned_at,
        attempted_at,
        user_id,
        tenant_id,
        one_off_job_id,
        method,
        url,
        req_headers,
        req_body,
        res_status_code,
        res_headers,
        res_body,
        response_time_ms,
        success
    )
VALUES (
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8,
        $9,
        $10,
        $11,
        $12,
        $13,
        $14,
        $15
    );"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.text(arg_6))
  |> pog.parameter(pog.text(arg_7))
  |> pog.parameter(pog.text(arg_8))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_9))
  |> pog.parameter(pog.text(arg_10))
  |> pog.parameter(pog.int(arg_11))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_12))
  |> pog.parameter(pog.text(arg_13))
  |> pog.parameter(pog.int(arg_14))
  |> pog.parameter(pog.bool(arg_15))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `list_errored_attempts` query
/// defined in `./src/joblot/instance/sql/list_errored_attempts.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ListErroredAttemptsRow {
  ListErroredAttemptsRow(
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

/// Runs the `list_errored_attempts` query
/// defined in `./src/joblot/instance/sql/list_errored_attempts.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn list_errored_attempts(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
) -> Result(pog.Returned(ListErroredAttemptsRow), pog.QueryError) {
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
    decode.success(ListErroredAttemptsRow(
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
WHERE planned_at = $1
    AND (
        one_off_job_id = $2
        OR cron_job_id = $2
    )
ORDER BY attempted_at ASC;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `list_responses` query
/// defined in `./src/joblot/instance/sql/list_responses.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ListResponsesRow {
  ListResponsesRow(
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

/// Runs the `list_responses` query
/// defined in `./src/joblot/instance/sql/list_responses.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn list_responses(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
) -> Result(pog.Returned(ListResponsesRow), pog.QueryError) {
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
    decode.success(ListResponsesRow(
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
WHERE planned_at = $1
    AND (
        one_off_job_id = $2
        OR cron_job_id = $2
    )
ORDER BY attempted_at ASC;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
