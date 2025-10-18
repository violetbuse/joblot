//// This module contains the code to run the sql queries defined in
//// `./src/joblot/instance/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

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

/// Runs the `set_one_off_job_complete` query
/// defined in `./src/joblot/instance/sql/set_one_off_job_complete.sql`.
///
/// > 🐿️ This function was generated automatically using v4.4.1 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn set_one_off_job_complete(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "UPDATE one_off_jobs
SET completed = true
WHERE id = $1;"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
