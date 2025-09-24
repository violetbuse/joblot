//// This module contains the code to run the sql queries defined in
//// `./src/joblot/api/one_off_jobs/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option}
import pog

/// A row you get from running the `create_one_off_job` query
/// defined in `./src/joblot/api/one_off_jobs/sql/create_one_off_job.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CreateOneOffJobRow {
  CreateOneOffJobRow(
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

/// Runs the `create_one_off_job` query
/// defined in `./src/joblot/api/one_off_jobs/sql/create_one_off_job.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn create_one_off_job(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: String,
  arg_4: String,
  arg_5: Json,
  arg_6: String,
  arg_7: String,
  arg_8: List(String),
  arg_9: String,
  arg_10: Int,
  arg_11: Int,
  arg_12: Bool,
  arg_13: Int,
) -> Result(pog.Returned(CreateOneOffJobRow), pog.QueryError) {
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
    decode.success(CreateOneOffJobRow(
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

  "INSERT INTO one_off_jobs (
        id,
        hash,
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
        timeout_ms
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
        $13
    )
RETURNING *;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(json.to_string(arg_5)))
  |> pog.parameter(pog.text(arg_6))
  |> pog.parameter(pog.text(arg_7))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_8))
  |> pog.parameter(pog.text(arg_9))
  |> pog.parameter(pog.int(arg_10))
  |> pog.parameter(pog.int(arg_11))
  |> pog.parameter(pog.bool(arg_12))
  |> pog.parameter(pog.int(arg_13))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `delete_one_off_job` query
/// defined in `./src/joblot/api/one_off_jobs/sql/delete_one_off_job.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_one_off_job(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "DELETE FROM one_off_jobs
WHERE id = $1
    AND user_id LIKE $2
    AND tenant_id LIKE $3;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_errored_attempts` query
/// defined in `./src/joblot/api/one_off_jobs/sql/get_errored_attempts.sql`.
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
  )
}

/// Runs the `get_errored_attempts` query
/// defined in `./src/joblot/api/one_off_jobs/sql/get_errored_attempts.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_errored_attempts(
  db: pog.Connection,
  arg_1: List(String),
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
    decode.success(GetErroredAttemptsRow(
      id:,
      planned_at:,
      attempted_at:,
      user_id:,
      tenant_id:,
      one_off_job_id:,
      cron_job_id:,
      error:,
    ))
  }

  "SELECT *
FROM errored_attempts
WHERE one_off_job_id = ANY($1::TEXT []);"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_one_off_job` query
/// defined in `./src/joblot/api/one_off_jobs/sql/get_one_off_job.sql`.
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
/// defined in `./src/joblot/api/one_off_jobs/sql/get_one_off_job.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_one_off_job(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
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
WHERE one_off_jobs.id = $1
    AND one_off_jobs.user_id LIKE $2
    AND one_off_jobs.tenant_id LIKE $3;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_responses` query
/// defined in `./src/joblot/api/one_off_jobs/sql/get_responses.sql`.
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
  )
}

/// Runs the `get_responses` query
/// defined in `./src/joblot/api/one_off_jobs/sql/get_responses.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_responses(
  db: pog.Connection,
  arg_1: List(String),
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
    ))
  }

  "SELECT *
FROM responses
WHERE one_off_job_id = ANY($1::TEXT []);"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `list_one_off_jobs` query
/// defined in `./src/joblot/api/one_off_jobs/sql/list_one_off_jobs.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ListOneOffJobsRow {
  ListOneOffJobsRow(
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

/// Runs the `list_one_off_jobs` query
/// defined in `./src/joblot/api/one_off_jobs/sql/list_one_off_jobs.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn list_one_off_jobs(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: String,
  arg_4: Int,
) -> Result(pog.Returned(ListOneOffJobsRow), pog.QueryError) {
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
    decode.success(ListOneOffJobsRow(
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
WHERE user_id LIKE $1
    AND tenant_id LIKE $2
    AND id > $3
ORDER BY id ASC
LIMIT $4;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.text(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
