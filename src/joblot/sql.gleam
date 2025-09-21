//// This module contains the code to run the sql queries defined in
//// `./src/joblot/sql`.
//// > 🐿️ This module was generated automatically using v4.4.1 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
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
        maximum_retries + 1 > attempts AND 
        execute_at <= $1 AND 
        executed_at IS NULL AND
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
