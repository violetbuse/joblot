//// This module contains the code to run the sql queries defined in
//// `./src/joblot/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option}
import pog

/// Runs the `clear_locks` query
/// defined in `./src/joblot/sql/clear_locks.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn clear_locks(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "delete from locks where expires_at < $1;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `create_one_off_job` query
/// defined in `./src/joblot/sql/create_one_off_job.sql`.
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
/// defined in `./src/joblot/sql/create_one_off_job.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn create_one_off_job(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: Int,
  arg_4: String,
  arg_5: String,
  arg_6: Json,
  arg_7: String,
  arg_8: String,
  arg_9: List(String),
  arg_10: String,
  arg_11: Int,
  arg_12: Int,
  arg_13: Bool,
  arg_14: Int,
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
        created_at,
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
        $13,
        $14
    )
RETURNING *;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.parameter(pog.text(json.to_string(arg_6)))
  |> pog.parameter(pog.text(arg_7))
  |> pog.parameter(pog.text(arg_8))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_9))
  |> pog.parameter(pog.text(arg_10))
  |> pog.parameter(pog.int(arg_11))
  |> pog.parameter(pog.int(arg_12))
  |> pog.parameter(pog.bool(arg_13))
  |> pog.parameter(pog.int(arg_14))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_errored_attempts_for` query
/// defined in `./src/joblot/sql/get_errored_attempts_for.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetErroredAttemptsForRow {
  GetErroredAttemptsForRow(
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

/// Runs the `get_errored_attempts_for` query
/// defined in `./src/joblot/sql/get_errored_attempts_for.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_errored_attempts_for(
  db: pog.Connection,
  arg_1: List(String),
  arg_2: List(String),
) -> Result(pog.Returned(GetErroredAttemptsForRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use planned_at <- decode.field(1, decode.int)
    use attempted_at <- decode.field(2, decode.int)
    use user_id <- decode.field(3, decode.string)
    use tenant_id <- decode.field(4, decode.string)
    use one_off_job_id <- decode.field(5, decode.optional(decode.string))
    use cron_job_id <- decode.field(6, decode.optional(decode.string))
    use error <- decode.field(7, decode.string)
    decode.success(GetErroredAttemptsForRow(
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
WHERE cron_job_id = ANY($1::TEXT [])
    OR one_off_job_id = ANY($2::TEXT []);"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_one_off_job` query
/// defined in `./src/joblot/sql/get_one_off_job.sql`.
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
/// defined in `./src/joblot/sql/get_one_off_job.sql`.
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

/// A row you get from running the `get_one_off_jobs` query
/// defined in `./src/joblot/sql/get_one_off_jobs.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetOneOffJobsRow {
  GetOneOffJobsRow(
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

/// Runs the `get_one_off_jobs` query
/// defined in `./src/joblot/sql/get_one_off_jobs.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_one_off_jobs(
  db: pog.Connection,
  arg_1: Int,
  arg_2: Int,
  arg_3: Bool,
  arg_4: String,
  arg_5: String,
) -> Result(pog.Returned(GetOneOffJobsRow), pog.QueryError) {
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
    decode.success(GetOneOffJobsRow(
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
WHERE execute_at >= $1
    AND execute_at <= $2
    AND completed = $3
    AND user_id LIKE $4
    AND tenant_id LIKE $5;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.bool(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.parameter(pog.text(arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `get_responses_for` query
/// defined in `./src/joblot/sql/get_responses_for.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type GetResponsesForRow {
  GetResponsesForRow(
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

/// Runs the `get_responses_for` query
/// defined in `./src/joblot/sql/get_responses_for.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn get_responses_for(
  db: pog.Connection,
  arg_1: List(String),
  arg_2: List(String),
) -> Result(pog.Returned(GetResponsesForRow), pog.QueryError) {
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
    decode.success(GetResponsesForRow(
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
WHERE cron_job_id = ANY($1::TEXT [])
    OR one_off_job_id = ANY($2::TEXT []);"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `insert_lock` query
/// defined in `./src/joblot/sql/insert_lock.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertLockRow {
  InsertLockRow(id: String, nonce: String, expires_at: Int)
}

/// Runs the `insert_lock` query
/// defined in `./src/joblot/sql/insert_lock.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_lock(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: Int,
) -> Result(pog.Returned(InsertLockRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use nonce <- decode.field(1, decode.string)
    use expires_at <- decode.field(2, decode.int)
    decode.success(InsertLockRow(id:, nonce:, expires_at:))
  }

  "insert into locks (id, nonce, expires_at) 
values ($1, $2, $3) 
on conflict (id, nonce)
do update set expires_at = $3
returning *;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `query_lock` query
/// defined in `./src/joblot/sql/query_lock.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type QueryLockRow {
  QueryLockRow(id: String, nonce: String, expires_at: Int)
}

/// Runs the `query_lock` query
/// defined in `./src/joblot/sql/query_lock.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn query_lock(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(QueryLockRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use nonce <- decode.field(1, decode.string)
    use expires_at <- decode.field(2, decode.int)
    decode.success(QueryLockRow(id:, nonce:, expires_at:))
  }

  "select * from locks where id = $1;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Runs the `release_lock` query
/// defined in `./src/joblot/sql/release_lock.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn release_lock(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "delete from locks where id = $1 and nonce = $2;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `scan_cron` query
/// defined in `./src/joblot/sql/scan_cron.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ScanCronRow {
  ScanCronRow(id: String)
}

/// Runs the `scan_cron` query
/// defined in `./src/joblot/sql/scan_cron.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn scan_cron(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
) -> Result(pog.Returned(ScanCronRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    decode.success(ScanCronRow(id:))
  }

  "SELECT id FROM cron_jobs
    WHERE
        id > $1
    ORDER BY id ASC
    LIMIT $2;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `scan_one_off_jobs` query
/// defined in `./src/joblot/sql/scan_one_off_jobs.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ScanOneOffJobsRow {
  ScanOneOffJobsRow(id: String)
}

/// Runs the `scan_one_off_jobs` query
/// defined in `./src/joblot/sql/scan_one_off_jobs.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn scan_one_off_jobs(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
  arg_3: Int,
) -> Result(pog.Returned(ScanOneOffJobsRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    decode.success(ScanOneOffJobsRow(id:))
  }

  "SELECT id FROM one_off_jobs 
    WHERE 
        execute_at <= $1 AND 
        completed = FALSE AND
        id > $2
    ORDER BY id ASC
    LIMIT $3;"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `update_lock` query
/// defined in `./src/joblot/sql/update_lock.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UpdateLockRow {
  UpdateLockRow(id: String, nonce: String, expires_at: Int)
}

/// Runs the `update_lock` query
/// defined in `./src/joblot/sql/update_lock.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn update_lock(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: Int,
) -> Result(pog.Returned(UpdateLockRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.string)
    use nonce <- decode.field(1, decode.string)
    use expires_at <- decode.field(2, decode.int)
    decode.success(UpdateLockRow(id:, nonce:, expires_at:))
  }

  "update locks set expires_at = $3 where id = $1 and nonce = $2 returning *;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
