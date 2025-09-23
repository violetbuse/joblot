//// This module contains the code to run the sql queries defined in
//// `./src/joblot/api/cron_jobs/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/json.{type Json}
import pog

/// A row you get from running the `create_cron_job` query
/// defined in `./src/joblot/api/cron_jobs/sql/create_cron_job.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.4.1 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CreateCronJobRow {
  CreateCronJobRow(
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

/// Runs the `create_cron_job` query
/// defined in `./src/joblot/api/cron_jobs/sql/create_cron_job.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn create_cron_job(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: String,
  arg_4: String,
  arg_5: Json,
  arg_6: String,
  arg_7: String,
  arg_8: String,
  arg_9: List(String),
  arg_10: String,
  arg_11: Int,
  arg_12: Bool,
  arg_13: Int,
) -> Result(pog.Returned(CreateCronJobRow), pog.QueryError) {
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
    decode.success(CreateCronJobRow(
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

  "INSERT INTO cron_jobs (
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
  |> pog.parameter(pog.text(arg_8))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_9))
  |> pog.parameter(pog.text(arg_10))
  |> pog.parameter(pog.int(arg_11))
  |> pog.parameter(pog.bool(arg_12))
  |> pog.parameter(pog.int(arg_13))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
